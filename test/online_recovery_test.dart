import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/models/domain/sincronizacao_backend.dart';
import 'package:studioflow/repositories/acesso_repository.dart';
import 'package:studioflow/services/acesso_online_service.dart';
import 'package:studioflow/services/backend_api_client.dart';
import 'package:studioflow/services/backend_token_vault.dart';

void main() {
  sqfliteFfiInit();

  test('login online recupera conta local após reinstalação', () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 13,
        onCreate: DatabaseSchemaLatest.criar,
      ),
    );
    addTearDown(db.close);
    final vault = _MemoryVault();
    final api = BackendApiClient(
      client: MockClient((request) async {
        expect(request.url.path, '/v1/auth/login');
        final body = jsonDecode(request.body) as Map;
        expect(body['password'], 'Senha@123');
        return http.Response(
          jsonEncode({
            'selectionRequired': false,
            'account': {
              'userId': 'user-online-1',
              'businessId': 'business-online-1',
              'businessName': 'Studio Recuperado',
              'userName': 'Dona Recuperada',
              'phone': '5511999999999',
              'login': 'dona@studioflow.test',
              'role': 'dono',
            },
            'accessToken': 'access-token-test',
            'refreshToken': 'refresh-token-test',
            'refreshTokenExpiresAt': DateTime.now()
                .toUtc()
                .add(const Duration(days: 30))
                .toIso8601String(),
          }),
          200,
        );
      }),
    );
    final repository = AcessoRepository(databaseProvider: () async => db);
    final online = AcessoOnlineService(
      api: api,
      vault: vault,
      repository: repository,
      endpoint: 'https://api.studioflow.test',
    );

    final result = await online.entrar(
      login: 'dona@studioflow.test',
      senha: 'Senha@123',
    );
    expect(result.usuario?.nomeComercio, 'Studio Recuperado');
    expect(await vault.read('business-online-1'), isNotNull);
    final local = await repository.autenticar(
      login: 'dona@studioflow.test',
      senha: 'Senha@123',
    );
    expect(local.single.id, 'user-online-1');
    final config = await db.query(
      'integracoes_configuracao',
      where: 'comercio_id=? AND sincronizacao_ativa=1',
      whereArgs: ['business-online-1'],
    );
    expect(config, hasLength(1));
  });
}

class _MemoryVault implements BackendTokenVault {
  final Map<String, SessaoBackend> sessions = {};
  @override
  Future<void> delete(String comercioId) async => sessions.remove(comercioId);
  @override
  Future<SessaoBackend?> read(String comercioId) async => sessions[comercioId];
  @override
  Future<void> write(SessaoBackend session) async {
    sessions[session.comercioId] = session;
  }
}
