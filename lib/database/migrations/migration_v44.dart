import 'package:sqflite/sqflite.dart';

abstract final class MigrationV44 {
  static Future<void> executar(Database db) async {
    await _addColumn(db, 'cobrancas', 'vencimento', 'TEXT');
    await _addColumn(
      db,
      'cobrancas',
      'valor_recebido',
      'REAL NOT NULL DEFAULT 0',
    );
    await db.execute('''CREATE TABLE IF NOT EXISTS cobranca_pagamentos (
      id TEXT PRIMARY KEY, cobranca_id TEXT NOT NULL, comercio_id TEXT NOT NULL,
      valor REAL NOT NULL, forma TEXT NOT NULL, registrado_em TEXT NOT NULL,
      estornado INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY(cobranca_id) REFERENCES cobrancas(id) ON DELETE RESTRICT
    )''');
  }

  static Future<void> _addColumn(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (columns.isNotEmpty && !columns.any((row) => row['name'] == column)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }
}
