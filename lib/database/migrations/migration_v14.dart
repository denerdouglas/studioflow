import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// Scanner comercial: origem pública e proteção multiempresa de código de barras.
abstract final class MigrationV14 {
  static Future<void> executar(Database db, {required bool criarBackup}) async {
    if (criarBackup) await _backup(db);

    final columns = await db.rawQuery('PRAGMA table_info(estoque)');
    if (!columns.any((item) => item['name'] == 'origem_catalogo')) {
      await db.execute(
        "ALTER TABLE estoque ADD COLUMN origem_catalogo TEXT NOT NULL DEFAULT 'manual'",
      );
    }

    await db.execute(
      'DROP TRIGGER IF EXISTS trg_estoque_barcode_unique_insert',
    );
    await db.execute(
      'DROP TRIGGER IF EXISTS trg_estoque_barcode_unique_update',
    );
    await db.execute('''CREATE TRIGGER trg_estoque_barcode_unique_insert
      BEFORE INSERT ON estoque
      WHEN NEW.codigo_barras IS NOT NULL AND TRIM(NEW.codigo_barras) <> ''
      BEGIN
        SELECT RAISE(ABORT, 'Código de barras já cadastrado neste comércio.')
        WHERE EXISTS (
          SELECT 1 FROM estoque
          WHERE comercio_id = NEW.comercio_id
            AND codigo_barras = NEW.codigo_barras
            AND estoque_destino = NEW.estoque_destino
        );
      END''');
    await db.execute('''CREATE TRIGGER trg_estoque_barcode_unique_update
      BEFORE UPDATE OF comercio_id, codigo_barras, estoque_destino ON estoque
      WHEN NEW.codigo_barras IS NOT NULL AND TRIM(NEW.codigo_barras) <> ''
      BEGIN
        SELECT RAISE(ABORT, 'Código de barras já cadastrado neste comércio.')
        WHERE EXISTS (
          SELECT 1 FROM estoque
          WHERE comercio_id = NEW.comercio_id
            AND codigo_barras = NEW.codigo_barras
            AND estoque_destino = NEW.estoque_destino
            AND id <> NEW.id
        );
      END''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_estoque_barcode_comercio '
      'ON estoque(comercio_id, estoque_destino, codigo_barras)',
    );
  }

  static Future<void> _backup(Database db) async {
    final now = DateTime.now().toUtc().toIso8601String();
    for (final table in [
      'estoque',
      'catalogo_produtos',
      'catalogo_sugestoes',
    ]) {
      final data = await db.query(table);
      final structure = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
        [table],
      );
      await db.insert('backups_logicos', {
        'versao_origem': 13,
        'tabela': table,
        'estrutura_sql': structure.isEmpty ? null : structure.first['sql'],
        'dados_json': jsonEncode(data),
        'criado_em': now,
      });
    }
  }
}
