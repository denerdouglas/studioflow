import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../core/utils/id_generator.dart';
import '../database/database_service.dart';
import '../models/domain/academy.dart';
import '../services/backend_api_client.dart';
import '../services/session_controller.dart';
import '../services/backend_token_vault.dart';

class AcademySearchResult {
  final List<AcademyCourse> courses;
  final int total;
  final String? source;

  AcademySearchResult({
    required this.courses,
    required this.total,
    this.source,
  });

  factory AcademySearchResult.fromJson(Map<String, dynamic> json) {
    return AcademySearchResult(
      courses: (json['data'] as List? ?? [])
          .map((e) => AcademyCourse.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int? ?? 0,
      source: json['source'] as String?,
    );
  }
}

class AcademyRepository {
  final BackendApiClient _api;
  final Future<Database> Function() _databaseProvider;
  final BackendTokenVault _vault;

  AcademyRepository({
    BackendApiClient? api,
    Future<Database> Function()? databaseProvider,
    BackendTokenVault? vault,
  })  : _api = api ?? BackendApiClient(),
        _databaseProvider = databaseProvider ?? (() => DatabaseService.instance.database),
        _vault = vault ?? const SecureBackendTokenVault();

  String get _comercioId {
    final usuario = SessionController.instance.usuario;
    if (usuario == null) throw StateError('Entre em sua conta para continuar.');
    return usuario.comercioId;
  }

  Future<Uri> _getEndpoint(Database db, String comercioId) async {
    final configRows = await db.query(
      'integracoes_configuracao',
      columns: ['endpoint_publico'],
      where: 'comercio_id = ?',
      whereArgs: [comercioId],
      limit: 1,
    );
    
    String endpointText = 'https://api.studioflowapp.com.br';
    if (configRows.isNotEmpty && configRows.single['endpoint_publico'] != null) {
      endpointText = configRows.single['endpoint_publico'] as String;
    }
    
    return _api.normalizeEndpoint(endpointText);
  }

  Future<AcademySearchResult> search({String? query, String? categoryId}) async {
    final db = await _databaseProvider();
    final comercioId = _comercioId;
    final queryNormalizada = '${query?.trim() ?? ''}_${categoryId ?? ''}'.toLowerCase();

    try {
      final endpoint = await _getEndpoint(db, comercioId);
      final session = await _vault.read(comercioId);
      
      if (session == null) {
        throw StateError('Sessão online indisponível. Conecte o backend.');
      }

      final response = await _api.academySearch(
        endpoint: endpoint, 
        accessToken: session.accessToken, 
        query: query,
        categoryId: categoryId,
      );
      
      final result = AcademySearchResult.fromJson(response);
      
      if (query != null && query.trim().isNotEmpty) {
        await _saveSearchHistory(db, comercioId, query.trim());
      }
      await _saveCache(db, comercioId, queryNormalizada, response);
      
      return result;
    } catch (e) {
      // Fallback to cache
      final cache = await _getCache(db, comercioId, queryNormalizada);
      if (cache != null) {
        return cache;
      }
      rethrow;
    }
  }

  Future<List<AcademyCategory>> getCategories() async {
    final db = await _databaseProvider();
    final comercioId = _comercioId;

    try {
      final endpoint = await _getEndpoint(db, comercioId);
      final session = await _vault.read(comercioId);
      
      if (session == null) {
        throw StateError('Sessão online indisponível. Conecte o backend.');
      }

      final response = await _api.academyCategories(
        endpoint: endpoint, 
        accessToken: session.accessToken,
      );
      
      final categoriesList = (response['data'] as List? ?? [])
          .map((e) => AcademyCategory.fromJson(e as Map<String, dynamic>))
          .toList();
          
      return categoriesList;
    } catch (e) {
      // Without cache for categories for simplicity, just rethrow
      rethrow;
    }
  }

  Future<void> _saveSearchHistory(Database db, String comercioId, String query) async {
    await db.insert('academy_search_history', {
      'id': IdGenerator.temporal(),
      'comercio_id': comercioId,
      'query': query,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _saveCache(Database db, String comercioId, String queryNormalizada, Map<String, dynamic> responseJson) async {
    await db.insert(
      'academy_search_cache',
      {
        'id': IdGenerator.temporal(),
        'comercio_id': comercioId,
        'query_normalizada': queryNormalizada,
        'response_json': jsonEncode(responseJson),
        'fetched_at': DateTime.now().toIso8601String(),
        'expires_at': DateTime.now().add(const Duration(hours: 24)).toIso8601String(),
        'backend_version': 'v1',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<AcademySearchResult?> _getCache(Database db, String comercioId, String queryNormalizada) async {
    final result = await db.query(
      'academy_search_cache',
      where: 'comercio_id = ? AND query_normalizada = ?',
      whereArgs: [comercioId, queryNormalizada],
    );

    if (result.isNotEmpty) {
      final row = result.first;
      final json = jsonDecode(row['response_json'] as String);
      return AcademySearchResult.fromJson(json);
    }
    return null;
  }
}
