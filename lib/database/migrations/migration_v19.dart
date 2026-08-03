import 'package:sqflite/sqflite.dart';

abstract final class MigrationV19 {
  static Future<void> executar(Database db, {bool criarBackup = false}) async {
    await db.execute('''
      CREATE TABLE academy_search_cache (
        id TEXT PRIMARY KEY,
        comercio_id TEXT NOT NULL,
        query_normalizada TEXT NOT NULL,
        response_json TEXT NOT NULL,
        fetched_at TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        backend_version TEXT,
        UNIQUE(comercio_id, query_normalizada)
      )
    ''');

    await db.execute('''
      CREATE TABLE academy_search_history (
        id TEXT PRIMARY KEY,
        comercio_id TEXT NOT NULL,
        query TEXT NOT NULL,
        timestamp TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE academy_favorites (
        id TEXT PRIMARY KEY,
        comercio_id TEXT NOT NULL,
        course_id TEXT NOT NULL,
        titulo TEXT NOT NULL,
        imagem TEXT,
        ultima_informacao_conhecida TEXT,
        favoritado_em TEXT NOT NULL,
        UNIQUE(comercio_id, course_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE academy_viewed_courses (
        id TEXT PRIMARY KEY,
        comercio_id TEXT NOT NULL,
        course_id TEXT NOT NULL,
        titulo TEXT NOT NULL,
        imagem TEXT,
        visto_em TEXT NOT NULL
      )
    ''');
  }
}
