import 'package:sqflite/sqflite.dart';

class MigrationV43 {
  static Future<void> executar(Database db) async {
    await _addColumn(db, 'insumos_json', 'TEXT');
  }

  static Future<void> _addColumn(
    Database db,
    String column,
    String definition,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info(servicos)');
    if (columns.isNotEmpty && !columns.any((row) => row['name'] == column)) {
      await db.execute('ALTER TABLE servicos ADD COLUMN $column $definition');
    }
  }
}
