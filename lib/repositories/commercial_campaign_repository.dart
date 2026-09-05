import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../database/database_service.dart';
import '../models/domain/commercial_campaign.dart';
import '../models/domain/global_course.dart';
import '../services/backend_api_client.dart';
import '../services/backend_token_vault.dart';
import '../services/session_controller.dart';

class CommercialCampaignRepository {
  static const cacheKey = '__commercial_campaigns_v1__';
  static const cacheTtl = Duration(hours: 24);
  final BackendApiClient _api;
  final Future<Database> Function() _databaseProvider;
  final BackendTokenVault _vault;

  CommercialCampaignRepository({
    BackendApiClient? api,
    Future<Database> Function()? databaseProvider,
    BackendTokenVault? vault,
  }) : _api = api ?? BackendApiClient(),
       _databaseProvider =
           databaseProvider ?? (() => DatabaseService.instance.database),
       _vault = vault ?? const SecureBackendTokenVault();

  String get _businessId {
    final user = SessionController.instance.usuario;
    if (user == null) throw StateError('Entre em sua conta para continuar.');
    return user.comercioId;
  }

  Future<List<CommercialCampaign>> list() async {
    final db = await _databaseProvider();
    final businessId = _businessId;
    try {
      final connection = await _connection(db, businessId);
      final response = await _api.campaignList(
        endpoint: connection.$1,
        accessToken: connection.$2,
      );
      await _saveCache(db, businessId, response);
      return decodeValid(response, DateTime.now());
    } catch (_) {
      return _cached(db, businessId, DateTime.now());
    }
  }

  Future<void> impression(String id) => _event(id, 'impressions');
  Future<void> click(String id) => _event(id, 'clicks');

  Future<List<GlobalCourse>> searchCourses(String query) async {
    final db = await _databaseProvider();
    final connection = await _connection(db, _businessId);
    final response = await _api.globalCourses(
      endpoint: connection.$1,
      accessToken: connection.$2,
      query: query,
    );
    return (response['courses'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => GlobalCourse.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<void> _event(String id, String type) async {
    final db = await _databaseProvider();
    final connection = await _connection(db, _businessId);
    await _api.campaignEvent(
      endpoint: connection.$1,
      accessToken: connection.$2,
      id: id,
      type: type,
    );
  }

  Future<(Uri, String)> _connection(Database db, String businessId) async {
    final rows = await db.query(
      'integracoes_configuracao',
      columns: ['endpoint_publico'],
      where: 'comercio_id = ?',
      whereArgs: [businessId],
      limit: 1,
    );
    final endpoint = rows.isEmpty || rows.first['endpoint_publico'] == null
        ? 'https://api.studioflowapp.com.br'
        : rows.first['endpoint_publico'] as String;
    final session = await _vault.read(businessId);
    if (session == null) throw StateError('Sessão online indisponível.');
    return (_api.normalizeEndpoint(endpoint), session.accessToken);
  }

  Future<void> _saveCache(
    Database db,
    String businessId,
    Map<String, dynamic> response,
  ) => db.insert('academy_search_cache', {
    'id': '$businessId:$cacheKey',
    'comercio_id': businessId,
    'query_normalizada': cacheKey,
    'response_json': jsonEncode(response),
    'fetched_at': DateTime.now().toIso8601String(),
    'expires_at': DateTime.now().add(cacheTtl).toIso8601String(),
    'backend_version': 'campaigns-v1',
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<CommercialCampaign>> _cached(
    Database db,
    String businessId,
    DateTime now,
  ) async {
    final rows = await db.query(
      'academy_search_cache',
      where: 'comercio_id = ? AND query_normalizada = ? AND expires_at > ?',
      whereArgs: [businessId, cacheKey, now.toIso8601String()],
      limit: 1,
    );
    if (rows.isEmpty) return const [];
    final response = Map<String, dynamic>.from(
      jsonDecode(rows.first['response_json'] as String) as Map,
    );
    return decodeValid(response, now);
  }

  static List<CommercialCampaign> decodeValid(
    Map<String, dynamic> response,
    DateTime now,
  ) => (response['campaigns'] as List? ?? const [])
      .whereType<Map>()
      .map(
        (item) => CommercialCampaign.fromJson(Map<String, dynamic>.from(item)),
      )
      .where((item) => item.isValidAt(now))
      .toList();
}
