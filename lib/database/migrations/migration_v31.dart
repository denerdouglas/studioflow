import 'package:sqflite/sqflite.dart';

abstract final class MigrationV31 {
  static Future<void> executar(Database db) async {
    // Adiciona chave de idempotência na movimentações_estoque para impedir consumo duplicado
    await _addColumn(db, 'movimentacoes_estoque', 'idempotency_key', 'TEXT');

    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_movimentacoes_idempotency 
      ON movimentacoes_estoque(idempotency_key) 
      WHERE idempotency_key IS NOT NULL
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
