import 'package:sqflite/sqflite.dart';

abstract final class MigrationV45 {
  static Future<void> executar(Database db) async {
    final comerciosInfo = await db.rawQuery('PRAGMA table_info(comercios)');
    if (comerciosInfo.isEmpty) return; // Se a tabela nem existir (ex: testes legados mocados), ignora

    final columns = comerciosInfo.map((e) => e['name'] as String).toList();
    if (!columns.contains('modulo_loja_ativo')) {
      await db.execute('ALTER TABLE comercios ADD COLUMN modulo_loja_ativo INTEGER NOT NULL DEFAULT 1');
    }
    if (!columns.contains('modulo_servicos_ativo')) {
      await db.execute('ALTER TABLE comercios ADD COLUMN modulo_servicos_ativo INTEGER NOT NULL DEFAULT 1');
    }
  }
}
