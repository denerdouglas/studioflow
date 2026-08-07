import 'package:sqflite/sqflite.dart';
import '../../models/domain/business_configuration.dart';
import '../database/database_service.dart';

/// Repositório para gerenciar configurações globais da empresa.
class BusinessConfigurationRepository {
  final DatabaseService _dbService;

  BusinessConfigurationRepository({DatabaseService? dbService})
    : _dbService = dbService ?? DatabaseService.instance;

  Future<Database> get _db async => _dbService.database;

  /// Retorna as configurações de um negócio. Retorna null se não houver.
  Future<BusinessConfiguration?> getByBusinessId(String businessId) async {
    final db = await _db;
    final results = await db.query(
      'business_configurations',
      where: 'business_id = ? AND deleted_at IS NULL',
      whereArgs: [businessId],
      limit: 1,
    );

    if (results.isEmpty) return null;
    return BusinessConfiguration.fromMap(results.first);
  }

  /// Cria ou atualiza as configurações do negócio.
  Future<void> save(BusinessConfiguration config) async {
    final db = await _db;
    await db.insert(
      'business_configurations',
      config.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Realiza soft-delete da configuração do negócio.
  Future<void> softDelete(
    String businessId, {
    required String updatedBy,
  }) async {
    final db = await _db;
    await db.update(
      'business_configurations',
      {
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
        'updated_by': updatedBy,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'business_id = ?',
      whereArgs: [businessId],
    );
  }
}
