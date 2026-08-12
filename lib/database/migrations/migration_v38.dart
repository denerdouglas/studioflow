import 'package:sqflite/sqflite.dart';

abstract final class MigrationV38 {
  static Future<void> executar(Database db) async {
    for (final column in const {
      'contrato': 'TEXT',
      'numero_mostruario': 'TEXT',
      'data_pagamento': 'TEXT',
      'observacoes': 'TEXT',
      'arquivo_origem': 'TEXT',
    }.entries) {
      await _addColumn(db, 'consignacoes', column.key, column.value);
    }
    await _addColumn(db, 'pecas_unicas', 'categoria', 'TEXT');
    await _addColumn(db, 'pecas_unicas', 'observacoes', 'TEXT');
    await _addColumn(db, 'consignacao_eventos', 'venda_id', 'TEXT');
    await _addColumn(db, 'consignacao_eventos', 'forma_pagamento', 'TEXT');

    final hasPieces = Sqflite.firstIntValue(
      await db.rawQuery(
        "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='pecas_unicas'",
      ),
    );
    if ((hasPieces ?? 0) == 0) return;

    // V24 tornou o código comercial único. Uma remessa, porém, pode conter
    // várias peças físicas com o mesmo código; a identidade é a coluna id.
    final indexes = await db.rawQuery("PRAGMA index_list('pecas_unicas')");
    for (final index in indexes) {
      if ((index['unique'] as num? ?? 0) != 1) continue;
      final name = index['name']?.toString();
      if (name == null || name.startsWith('sqlite_autoindex')) continue;
      final columns = await db.rawQuery("PRAGMA index_info('$name')");
      final names = columns.map((row) => row['name']).toList();
      if (names.length == 2 &&
          names.contains('comercio_id') &&
          names.contains('codigo_exclusivo')) {
        await db.execute('DROP INDEX IF EXISTS "$name"');
      }
    }

    // SQLite materializa UNIQUE de CREATE TABLE como autoindex, que não pode
    // ser removido. Reconstruímos somente quando ele ainda estiver presente.
    final sql = (await db.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type='table' AND name='pecas_unicas'",
    )).firstOrNull?['sql']?.toString().toLowerCase();
    if (sql?.contains('unique(comercio_id, codigo_exclusivo)') ?? false) {
      final originalCount =
          Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM pecas_unicas'),
          ) ??
          0;
      await db.execute('ALTER TABLE pecas_unicas RENAME TO pecas_unicas_v24');
      await db.execute('''CREATE TABLE pecas_unicas (
        id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL,
        codigo_exclusivo TEXT NOT NULL, nome TEXT NOT NULL, descricao TEXT,
        material TEXT, marca TEXT, fornecedor_id TEXT, custo REAL NOT NULL DEFAULT 0,
        preco REAL NOT NULL, lote_id TEXT, unidade_id TEXT, localizacao TEXT,
        cliente_id TEXT, profissional_vendedor_id TEXT, comissao REAL,
        data_venda TEXT, status TEXT NOT NULL DEFAULT 'disponivel',
        data_cadastro TEXT NOT NULL, categoria TEXT, observacoes TEXT
      )''');
      await db.execute('''INSERT INTO pecas_unicas (
        id, comercio_id, codigo_exclusivo, nome, descricao, material, marca,
        fornecedor_id, custo, preco, lote_id, unidade_id, localizacao,
        cliente_id, profissional_vendedor_id, comissao, data_venda, status,
        data_cadastro, categoria, observacoes)
        SELECT id, comercio_id, codigo_exclusivo, nome, descricao, material, marca,
        fornecedor_id, custo, preco, lote_id, unidade_id, localizacao,
        cliente_id, profissional_vendedor_id, comissao, data_venda, status,
        data_cadastro, categoria, observacoes FROM pecas_unicas_v24''');
      final copiedCount =
          Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM pecas_unicas'),
          ) ??
          0;
      if (copiedCount != originalCount) {
        throw StateError(
          'Migração V38 interrompida: $copiedCount de $originalCount peças foram copiadas.',
        );
      }
      await db.execute('DROP TABLE pecas_unicas_v24');
    }
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_pecas_lote_status_codigo
      ON pecas_unicas(comercio_id, lote_id, status, codigo_exclusivo)''');
    final hasConsignments = Sqflite.firstIntValue(
      await db.rawQuery(
        "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='consignacoes'",
      ),
    );
    if ((hasConsignments ?? 0) > 0) {
      await db.execute(
        '''CREATE INDEX IF NOT EXISTS idx_consignacoes_status_datas
        ON consignacoes(comercio_id, status, recebida_em)''',
      );
    }
  }

  static Future<void> _addColumn(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final exists = Sqflite.firstIntValue(
      await db.rawQuery(
        "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=?",
        [table],
      ),
    );
    if ((exists ?? 0) == 0) return;
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (!columns.any((row) => row['name'] == column)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }
}
