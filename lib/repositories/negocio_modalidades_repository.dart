import 'package:sqflite/sqflite.dart';
import '../../models/domain/negocio_modalidade.dart';
import '../../core/enums/tipo_modalidade.dart';
import '../database/database_service.dart';

/// Repositório para as modalidades ativas de uma empresa.
class NegocioModalidadesRepository {
  final DatabaseService _dbService;

  NegocioModalidadesRepository({DatabaseService? dbService})
    : _dbService = dbService ?? DatabaseService.instance;

  Future<Database> get _db async => _dbService.database;

  /// Retorna todas as modalidades de uma empresa.
  Future<List<NegocioModalidade>> getByBusinessId(String businessId) async {
    final db = await _db;
    final results = await db.query(
      'negocio_modalidades',
      where: 'business_id = ? AND deleted_at IS NULL',
      whereArgs: [businessId],
      orderBy: 'ordem_exibicao ASC',
    );
    return results.map((e) => NegocioModalidade.fromMap(e)).toList();
  }

  /// Retorna a modalidade principal ativa de um negócio.
  Future<NegocioModalidade?> getPrincipalActive(String businessId) async {
    final db = await _db;
    final results = await db.query(
      'negocio_modalidades',
      where:
          'business_id = ? AND tipo = ? AND ativo = 1 AND deleted_at IS NULL',
      whereArgs: [businessId, TipoModalidade.principal.nome],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return NegocioModalidade.fromMap(results.first);
  }

  /// Salva a ativação de uma modalidade.
  Future<void> save(NegocioModalidade modalidade) async {
    final db = await _db;
    await db.insert(
      'negocio_modalidades',
      modalidade.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Desativa uma modalidade por completo.
  Future<void> deactivate(String id, {required String updatedBy}) async {
    final db = await _db;
    await db.update(
      'negocio_modalidades',
      {
        'ativo': 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'updated_by': updatedBy,
      },
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
  }
}
