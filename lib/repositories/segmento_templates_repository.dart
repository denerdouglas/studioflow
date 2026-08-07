import 'package:sqflite/sqflite.dart';
import '../../models/domain/segmento_template.dart';
import '../database/database_service.dart';
import '../services/segmento_seeder.dart';

/// Repositório para gerenciar os templates de segmento disponíveis no sistema.
class SegmentoTemplatesRepository {
  final DatabaseService _dbService;

  SegmentoTemplatesRepository({DatabaseService? dbService})
    : _dbService = dbService ?? DatabaseService.instance;

  Future<Database> get _db async => _dbService.database;

  /// Retorna todos os templates ativos.
  Future<List<SegmentoTemplate>> getAllActive() async {
    final db = await _db;
    final results = await db.query(
      'segmento_templates',
      where: 'status = ? AND deleted_at IS NULL',
      whereArgs: ['ativo'],
    );
    if (results.isEmpty) {
      await SegmentoSeeder(repo: this).seedTemplates();
      final retryResults = await db.query(
        'segmento_templates',
        where: 'status = ? AND deleted_at IS NULL',
        whereArgs: ['ativo'],
      );
      return retryResults.map((e) => SegmentoTemplate.fromMap(e)).toList();
    }
    return results.map((e) => SegmentoTemplate.fromMap(e)).toList();
  }

  /// Busca um template por slug.
  Future<SegmentoTemplate?> getBySlug(String slug) async {
    final db = await _db;
    final results = await db.query(
      'segmento_templates',
      where: 'slug = ? AND deleted_at IS NULL',
      whereArgs: [slug],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return SegmentoTemplate.fromMap(results.first);
  }

  /// Salva ou atualiza um template global.
  Future<void> save(SegmentoTemplate template) async {
    final db = await _db;
    await db.insert(
      'segmento_templates',
      template.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
