import 'package:sqflite/sqflite.dart';

abstract final class MigrationV20 {
  static Future<void> executar(Database db, {bool criarBackup = false}) async {
    // Adicionando novos campos no cadastro do comércio para Fase 2
    final comerciosInfo = await db.rawQuery("PRAGMA table_info('comercios')");
    final columns = comerciosInfo.map((c) => c['name'] as String).toSet();

    if (!columns.contains('documento_tipo')) {
      await db.execute('ALTER TABLE comercios ADD COLUMN documento_tipo TEXT');
    }
    if (!columns.contains('documento')) {
      await db.execute('ALTER TABLE comercios ADD COLUMN documento TEXT');
    }
    if (!columns.contains('inscricao_estadual')) {
      await db.execute('ALTER TABLE comercios ADD COLUMN inscricao_estadual TEXT');
    }
    if (!columns.contains('whatsapp')) {
      await db.execute('ALTER TABLE comercios ADD COLUMN whatsapp TEXT');
    }
    if (!columns.contains('instagram')) {
      await db.execute('ALTER TABLE comercios ADD COLUMN instagram TEXT');
    }
    if (!columns.contains('cep')) {
      await db.execute('ALTER TABLE comercios ADD COLUMN cep TEXT');
    }
    if (!columns.contains('endereco')) {
      await db.execute('ALTER TABLE comercios ADD COLUMN endereco TEXT');
    }
    if (!columns.contains('numero')) {
      await db.execute('ALTER TABLE comercios ADD COLUMN numero TEXT');
    }
    if (!columns.contains('complemento')) {
      await db.execute('ALTER TABLE comercios ADD COLUMN complemento TEXT');
    }
    if (!columns.contains('bairro')) {
      await db.execute('ALTER TABLE comercios ADD COLUMN bairro TEXT');
    }
    if (!columns.contains('cidade')) {
      await db.execute('ALTER TABLE comercios ADD COLUMN cidade TEXT');
    }
    if (!columns.contains('estado')) {
      await db.execute('ALTER TABLE comercios ADD COLUMN estado TEXT');
    }
    if (!columns.contains('capa_url')) {
      await db.execute('ALTER TABLE comercios ADD COLUMN capa_url TEXT');
    }
  }
}
