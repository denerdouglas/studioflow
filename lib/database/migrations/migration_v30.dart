import 'package:sqflite/sqflite.dart';

abstract final class MigrationV30 {
  static Future<void> executar(Database db) async {
    // 1. Tabela de grupos de agendamento
    await db.execute('''
      CREATE TABLE IF NOT EXISTS agendamento_grupos (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        cliente_id TEXT NOT NULL,
        comanda_id TEXT,
        status TEXT,
        observacoes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        created_by TEXT,
        updated_by TEXT
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_agendamento_grupos_business
      ON agendamento_grupos(business_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_agendamento_grupos_cliente
      ON agendamento_grupos(cliente_id)
    ''');

    // 2. Garantir compatibilidade com bancos antigos
    await _addColumn(db, 'agendamentos', 'business_id', 'TEXT');

    await _backfillBusinessId(db);

    // 3. Campos da Fase 4.2
    await _addColumn(db, 'agendamentos', 'grupo_agendamento_id', 'TEXT');

    await _addColumn(
      db,
      'agendamentos',
      'ordem_no_grupo',
      'INTEGER NOT NULL DEFAULT 0',
    );

    // 4. Índice criado somente depois das colunas existirem
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_agendamentos_grupo
      ON agendamentos(business_id, grupo_agendamento_id)
    ''');
  }

  static Future<void> _backfillBusinessId(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(agendamentos)');

    final hasBusinessId = columns.any(
      (column) => column['name'] == 'business_id',
    );

    final hasComercioId = columns.any(
      (column) => column['name'] == 'comercio_id',
    );

    if (!hasBusinessId || !hasComercioId) {
      return;
    }

    await db.execute('''
      UPDATE agendamentos
      SET business_id = comercio_id
      WHERE business_id IS NULL
        AND comercio_id IS NOT NULL
    ''');
  }

  static Future<void> _addColumn(
    Database db,
    String table,
    String column,
    String type,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');

    final exists = columns.any((item) => item['name'] == column);

    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    }
  }
}
