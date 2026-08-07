import 'package:sqflite/sqflite.dart';

abstract final class MigrationV30 {
  static Future<void> executar(Database db) async {
    // 1. Tabela agendamento_grupos
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
      CREATE INDEX idx_agendamento_grupos_business ON agendamento_grupos(business_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_agendamento_grupos_cliente ON agendamento_grupos(cliente_id)
    ''');

    // 2. Adicionar campos em agendamentos
    await _addColumn(db, 'agendamentos', 'grupo_agendamento_id', 'TEXT');
    await _addColumn(
      db,
      'agendamentos',
      'ordem_no_grupo',
      'INTEGER NOT NULL DEFAULT 0',
    );

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_agendamentos_grupo ON agendamentos(business_id, grupo_agendamento_id)
    ''');
  }

  static Future<void> _addColumn(
    Database db,
    String table,
    String column,
    String type,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final exists = columns.any((c) => c['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    }
  }
}
