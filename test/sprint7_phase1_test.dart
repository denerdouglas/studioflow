import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/models/domain/sincronizacao_backend.dart';
import 'package:studioflow/services/backend_api_client.dart';
import 'package:studioflow/services/backend_sync_service.dart';
import 'package:studioflow/services/backend_token_vault.dart';

void main() {
  sqfliteFfiInit();

  test(
    'snapshot local entra na fila, sincroniza e registra versão remota',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 9,
          onConfigure: (database) =>
              database.execute('PRAGMA foreign_keys = ON'),
          onCreate: DatabaseSchemaLatest.criar,
        ),
      );
      addTearDown(db.close);
      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert('comercios', {
        'id': 'com_sync_test',
        'codigo_acesso': 'SYNC1234',
        'nome': 'Studio Sync',
        'nome_exibicao': 'Studio Sync',
        'responsavel': 'Dona',
        'telefone': '11999999999',
        'email': 'dona@sync.test',
        'ativo': 1,
        'criado_em': now,
        'atualizado_em': now,
      });
      await db.insert('usuarios', {
        'id': 'user_sync_test',
        'comercio_id': 'com_sync_test',
        'nome': 'Dona',
        'telefone': '11999999999',
        'email_login': 'dona@sync.test',
        'senha_hash': 'hash',
        'senha_salt': 'salt',
        'funcao': 'dono',
        'ativo': 1,
        'criado_em': now,
        'atualizado_em': now,
      });
      await db.insert('unidades', {
        'id': 'uni_sync_test',
        'comercio_id': 'com_sync_test',
        'nome': 'Matriz',
        'codigo': 'MATRIZ',
        'principal': 1,
        'ativo': 1,
        'criado_em': now,
        'atualizado_em': now,
      });
      await db.insert('integracoes_configuracao', {
        'comercio_id': 'com_sync_test',
        'provedor_backend': 'studioflow_rest',
        'endpoint_publico': 'https://api.studioflow.test',
        'sincronizacao_ativa': 1,
        'atualizado_em': now,
      });
      await db.insert('clientes', {
        'id': 'cliente_sync_test',
        'comercio_id': 'com_sync_test',
        'nome': 'Cliente sincronizada',
        'whatsapp': '11988887777',
        'ativo': 1,
        'data_cadastro': now,
        'total_atendimentos': 0,
        'total_gasto': 0,
        'pontos_fidelidade': 0,
      });
      final vault = _MemoryVault(
        SessaoBackend(
          comercioId: 'com_sync_test',
          usuarioId: 'user_sync_test',
          accessToken: 'access',
          refreshToken: 'refresh',
          refreshExpiraEm: DateTime.now().toUtc().add(const Duration(days: 1)),
        ),
      );
      final service = BackendSyncService(
        databaseProvider: () async => db,
        api: _FakeApi(),
        vault: vault,
      );

      final result = await service.sincronizar('com_sync_test');
      expect(result.enviadas, greaterThan(0));
      expect(result.conflitos, 0);
      expect(result.pendentes, 0);
      expect(
        await db.query(
          'registro_sync_estado',
          where: 'comercio_id = ? AND entidade = ? AND entidade_id = ?',
          whereArgs: ['com_sync_test', 'clientes', 'cliente_sync_test'],
        ),
        hasLength(1),
      );
      expect(
        await db.query(
          'fila_sincronizacao',
          where: "comercio_id = ? AND status = 'sincronizado'",
          whereArgs: ['com_sync_test'],
        ),
        isNotEmpty,
      );
    },
  );

  test('endpoint inseguro externo é rejeitado', () {
    final api = BackendApiClient();
    expect(
      () => api.normalizeEndpoint('http://api.studioflow.test'),
      throwsFormatException,
    );
    expect(
      api.normalizeEndpoint('https://api.studioflow.test').scheme,
      'https',
    );
  });
}

class _FakeApi extends BackendApiClient {
  @override
  Future<Map<String, dynamic>> push({
    required Uri endpoint,
    required String accessToken,
    required List<Map<String, Object?>> operations,
  }) async {
    return {
      'results': [
        for (final operation in operations)
          {
            'operationId': operation['operationId'],
            'status': 'applied',
            'serverVersion': 1,
            'serverPayload': operation['payload'],
          },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> pull({
    required Uri endpoint,
    required String accessToken,
    required int cursor,
    int limit = 200,
  }) async {
    return {'changes': <Object?>[], 'nextCursor': cursor};
  }
}

class _MemoryVault implements BackendTokenVault {
  SessaoBackend? session;

  _MemoryVault(this.session);

  @override
  Future<void> delete(String comercioId) async => session = null;

  @override
  Future<SessaoBackend?> read(String comercioId) async => session;

  @override
  Future<void> write(SessaoBackend session) async => this.session = session;
}
