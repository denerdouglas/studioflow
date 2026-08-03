import 'package:sqflite/sqflite.dart';

abstract final class MigrationV16 {
  static Future<void> executar(Database db, {required bool criarBackup}) async {
    if (criarBackup) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS estoque_v15_backup AS SELECT * FROM estoque
      ''');
    }

    // Adiciona as novas colunas
    await _adicionarColuna(
      db,
      'estoque',
      'conteudo_por_unidade',
      'REAL NOT NULL DEFAULT 1',
    );
    await _adicionarColuna(
      db,
      'estoque',
      'unidade_conteudo',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _adicionarColuna(
      db,
      'estoque',
      'revisao_modelagem_estoque',
      'INTEGER NOT NULL DEFAULT 0',
    );

    // Identificar registros antigos com unidades de medida de conteúdo
    final unidadesConteudo = [
      'g',
      'kg',
      'grama',
      'gramas',
      'ml',
      'l',
      'litro',
      'litros',
    ];

    final inClause = unidadesConteudo.map((u) => "'$u'").join(', ');

    // Marcar para revisão os produtos que utilizavam unidade de peso/volume no campo unidade
    await db.execute('''
      UPDATE estoque
      SET revisao_modelagem_estoque = 1
      WHERE LOWER(TRIM(unidade)) IN ($inClause)
    ''');
  }

  static Future<void> _adicionarColuna(
    Database db,
    String tabela,
    String coluna,
    String definicao,
  ) async {
    final colunas = await db.rawQuery('PRAGMA table_info($tabela)');
    if (!colunas.any((item) => item['name'] == coluna)) {
      await db.execute('ALTER TABLE $tabela ADD COLUMN $coluna $definicao');
    }
  }
}
