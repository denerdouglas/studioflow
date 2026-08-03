import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../core/utils/id_generator.dart';
import '../database/database_service.dart';
import '../models/domain/marketplace.dart';
import '../services/backend_api_client.dart';
import '../services/session_controller.dart';
import '../services/backend_token_vault.dart';

class MarketplaceRepository {
  final BackendApiClient _api;
  final Future<Database> Function() _databaseProvider;
  final BackendTokenVault _vault;

  MarketplaceRepository({
    BackendApiClient? api,
    Future<Database> Function()? databaseProvider,
    BackendTokenVault? vault,
  }) : _api = api ?? BackendApiClient(),
       _databaseProvider =
           databaseProvider ?? (() => DatabaseService.instance.database),
       _vault = vault ?? const SecureBackendTokenVault();

  String get _comercioId {
    final usuario = SessionController.instance.usuario;
    if (usuario == null) throw StateError('Entre em sua conta para continuar.');
    return usuario.comercioId;
  }

  Future<MarketplaceSearchResult> search(String query) async {
    final db = await _databaseProvider();
    final comercioId = _comercioId;

    try {
      final configRows = await db.query(
        'integracoes_configuracao',
        columns: ['endpoint_publico'],
        where: 'comercio_id = ?',
        whereArgs: [comercioId],
        limit: 1,
      );

      String endpointText = 'https://api.studioflowapp.com.br';
      if (configRows.isNotEmpty &&
          configRows.single['endpoint_publico'] != null) {
        endpointText = configRows.single['endpoint_publico'] as String;
      }

      final endpoint = _api.normalizeEndpoint(endpointText);
      final session = await _vault.read(comercioId);

      if (session == null) {
        throw StateError('Sessão online indisponível. Conecte o backend.');
      }

      final response = await _api.marketplaceSearch(
        endpoint: endpoint,
        accessToken: session.accessToken,
        query: query,
      );

      final result = MarketplaceSearchResult.fromJson(response);
      await _saveSearchHistory(db, comercioId, query);
      await _saveCache(db, comercioId, query, response);
      return result;
    } catch (e) {
      // Fallback to cache
      final cache = await _getCache(db, comercioId, query);
      if (cache != null) {
        return cache;
      }
      rethrow;
    }
  }

  Future<void> _saveSearchHistory(
    Database db,
    String comercioId,
    String query,
  ) async {
    await db.insert('marketplace_search_history', {
      'id': IdGenerator.temporal(),
      'comercio_id': comercioId,
      'query': query,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _saveCache(
    Database db,
    String comercioId,
    String query,
    Map<String, dynamic> responseJson,
  ) async {
    final queryNormalizada = query.trim().toLowerCase();
    await db.insert('marketplace_search_cache', {
      'id': IdGenerator.temporal(),
      'comercio_id': comercioId,
      'query_normalizada': queryNormalizada,
      'response_json': jsonEncode(responseJson),
      'fetched_at': DateTime.now().toIso8601String(),
      'expires_at': DateTime.now()
          .add(const Duration(hours: 24))
          .toIso8601String(),
      'backend_version': 'v1',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<MarketplaceSearchResult?> _getCache(
    Database db,
    String comercioId,
    String query,
  ) async {
    final queryNormalizada = query.trim().toLowerCase();
    final result = await db.query(
      'marketplace_search_cache',
      where: 'comercio_id = ? AND query_normalizada = ?',
      whereArgs: [comercioId, queryNormalizada],
    );

    if (result.isNotEmpty) {
      final row = result.first;
      final json = jsonDecode(row['response_json'] as String);
      return MarketplaceSearchResult.fromJson(json);
    }
    return null;
  }
}
