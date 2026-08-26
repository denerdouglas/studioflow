import 'package:sqflite/sqflite.dart';

abstract final class MigrationV46 {
  static Future<void> executar(Database db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='comercios'",
    );
    if (tables.isEmpty) return;
    final columns = (await db.rawQuery(
      'PRAGMA table_info(comercios)',
    )).map((row) => row['name']).toSet();
    if (!columns.contains('modulos_configuracao_json')) {
      await db.execute(
        'ALTER TABLE comercios ADD COLUMN modulos_configuracao_json TEXT',
      );
    }
  }
}
