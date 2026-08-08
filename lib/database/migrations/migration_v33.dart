import 'package:sqflite/sqflite.dart';

abstract final class MigrationV33 {
  static Future<void> executar(Database db) async {
    // Garante a existência da nova fonte de verdade dos saldos.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS estoque_saldos (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        estoque_id TEXT NOT NULL,
        finalidade TEXT NOT NULL,
        local_id TEXT,
        quantidade_atual REAL DEFAULT 0,
        quantidade_reservada REAL DEFAULT 0,
        estoque_minimo REAL,
        estoque_maximo REAL,
        estoque_ideal REAL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        created_by TEXT,
        updated_by TEXT,
        FOREIGN KEY (estoque_id)
          REFERENCES estoque (id)
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_estoque_saldos_uniq
      ON estoque_saldos (
        business_id,
        estoque_id,
        finalidade,
        COALESCE(local_id, '')
      )
      WHERE deleted_at IS NULL
    ''');

    await _garantirColunasAgendamentos(db);
    await _migrarSaldosLegados(db);
  }

  static Future<void> _addColumn(
    Database db,
    String table,
    String column,
    String type,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final hasColumn = columns.any((c) => c['name'] == column);
    if (!hasColumn) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    }
  }

  static Future<void> _garantirColunasAgendamentos(Database db) async {
    await _addColumn(db, 'agendamentos', 'business_id', 'TEXT');
    await _addColumn(db, 'agendamentos', 'comercio_id', 'TEXT');
    await _addColumn(db, 'agendamentos', 'grupo_agendamento_id', 'TEXT');
    await _addColumn(
      db,
      'agendamentos',
      'ordem_no_grupo',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumn(db, 'agendamentos', 'consumo_previsto_json', 'TEXT');
    await _addColumn(db, 'agendamentos', 'consumo_realizado_json', 'TEXT');
    await _addColumn(
      db,
      'agendamentos',
      'estoque_consumido',
      'INTEGER DEFAULT 0',
    );
    await _addColumn(db, 'agendamentos', 'created_by', 'TEXT');
    await _addColumn(db, 'agendamentos', 'updated_by', 'TEXT');
    await _addColumn(db, 'agendamentos', 'created_at', 'TEXT');
    await _addColumn(db, 'agendamentos', 'updated_at', 'TEXT');
    await _addColumn(db, 'agendamentos', 'deleted_at', 'TEXT');
    await _addColumn(db, 'agendamentos', 'encaixe', 'INTEGER DEFAULT 0');
  }

  static Future<void> _migrarSaldosLegados(Database db) async {
    final colunas = await db.rawQuery('PRAGMA table_info(estoque)');

    bool possui(String nome) => colunas.any((coluna) => coluna['name'] == nome);

    final possuiBusinessId = possui('business_id');
    final possuiComercioId = possui('comercio_id');
    final possuiTipoProduto = possui('tipo_produto');

    // Sem identificador do negócio não é seguro fabricar business_id.
    // O LEFT JOIN dos repositories continuará usando o saldo legado
    // da própria tabela estoque via COALESCE.
    if (!possuiBusinessId && !possuiComercioId) {
      return;
    }

    final itens = await db.query('estoque');
    final agora = DateTime.now().toUtc().toIso8601String();

    for (final item in itens) {
      final estoqueId = item['id']?.toString();

      final businessId = possuiBusinessId && item['business_id'] != null
          ? item['business_id']?.toString()
          : possuiComercioId
          ? item['comercio_id']?.toString()
          : null;

      if (estoqueId == null ||
          estoqueId.isEmpty ||
          businessId == null ||
          businessId.isEmpty) {
        continue;
      }

      final tipoProduto = possuiTipoProduto
          ? item['tipo_produto']?.toString().toLowerCase()
          : null;

      final quantidade = (item['quantidade_atual'] as num?)?.toDouble() ?? 0;

      final minimo = (item['estoque_minimo'] as num?)?.toDouble() ?? 0;

      final maximo = (item['estoque_maximo'] as num?)?.toDouble();

      final ideal = (item['estoque_ideal'] as num?)?.toDouble();

      if (tipoProduto == 'ativo_imobilizado') {
        continue;
      }

      if (tipoProduto == 'ambos') {
        // Não duplicamos o estoque legado.
        // O saldo existente fica em uso interno e a finalidade
        // comercial nasce zerada para futura separação real.
        await _inserirSaldo(
          db,
          businessId: businessId,
          estoqueId: estoqueId,
          finalidade: 'uso_interno',
          quantidade: quantidade,
          minimo: minimo,
          maximo: maximo,
          ideal: ideal,
          agora: agora,
        );

        await _inserirSaldo(
          db,
          businessId: businessId,
          estoqueId: estoqueId,
          finalidade: 'venda',
          quantidade: 0,
          minimo: minimo,
          maximo: maximo,
          ideal: ideal,
          agora: agora,
        );

        continue;
      }

      final finalidade = tipoProduto == 'venda' ? 'venda' : 'uso_interno';

      await _inserirSaldo(
        db,
        businessId: businessId,
        estoqueId: estoqueId,
        finalidade: finalidade,
        quantidade: quantidade,
        minimo: minimo,
        maximo: maximo,
        ideal: ideal,
        agora: agora,
      );
    }
  }

  static Future<void> _inserirSaldo(
    Database db, {
    required String businessId,
    required String estoqueId,
    required String finalidade,
    required double quantidade,
    required double minimo,
    required double? maximo,
    required double? ideal,
    required String agora,
  }) async {
    final id = 'saldo_${businessId}_${estoqueId}_$finalidade';

    await db.insert('estoque_saldos', {
      'id': id,
      'business_id': businessId,
      'estoque_id': estoqueId,
      'finalidade': finalidade,
      'local_id': null,
      'quantidade_atual': quantidade,
      'quantidade_reservada': 0,
      'estoque_minimo': minimo,
      'estoque_maximo': maximo,
      'estoque_ideal': ideal,
      'created_at': agora,
      'updated_at': agora,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
}
