import 'package:sqflite/sqflite.dart';

abstract final class MigrationV36 {
  static Future<void> executar(Database db) async {
    final colunas = await db.rawQuery('PRAGMA table_info(estoque)');
    final nomes = colunas
        .map((coluna) => coluna['name']?.toString().toLowerCase())
        .whereType<String>()
        .toSet();

    if (!nomes.contains('business_id')) {
      await db.execute('ALTER TABLE estoque ADD COLUMN business_id TEXT');
    }

    if (nomes.contains('comercio_id')) {
      await db.execute('''
        UPDATE estoque
        SET business_id = comercio_id
        WHERE (business_id IS NULL OR business_id = '')
          AND comercio_id IS NOT NULL
          AND comercio_id != ''
      ''');
    }
  }
}
