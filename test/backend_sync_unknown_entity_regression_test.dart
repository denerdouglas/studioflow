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
    'entidade desconhecida nao bloqueia cliente profissional servico e agendamento',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 37,
          onConfigure: (database) =>
              database.execute('PRAGMA foreign_keys = ON'),
          onCreate: DatabaseSchemaLatest.criar,
        ),
      );
      addTearDown(db.close);

      final now = DateTime.now().toUtc().toIso8601String();
      const comercioId = 'com_sync_unknown_test';

      await db.insert('comercios', {
        'id': comercioId,
        'codigo_acesso': 'SYNCUNKNOWN',
        'nome': 'Studio Sync Unknown',
        'nome_exibicao': 'Studio Sync Unknown',
        'responsavel': 'Dona',
        'telefone': '11999999999',
        'email': 'dona@sync.test',
        'ativo': 1,
        'criado_em': now,
        'atualizado_em': now,
      });

      await db.insert('integracoes_configuracao', {
        'comercio_id': comercioId,
        'provedor_backend': 'studioflow_rest',
        'endpoint_publico': 'https://api.studioflow.test',
        'sincronizacao_ativa': 1,
        'ultimo_cursor': 0,
        'atualizado_em': now,
      });

      final vault = _MemoryVault(
        SessaoBackend(
          comercioId: comercioId,
          usuarioId: 'user_sync_unknown',
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

      final result = await service.sincronizar(comercioId);

      expect(result.recebidas, 4);

      expect(
        await db.query(
          'clientes',
          where: 'id = ? AND comercio_id = ?',
          whereArgs: ['cliente_remoto_ok', comercioId],
        ),
        hasLength(1),
      );

      expect(
        await db.query(
          'profissionais',
          where: 'id = ? AND comercio_id = ?',
          whereArgs: ['profissional_remoto_ok', comercioId],
        ),
        hasLength(1),
      );

      expect(
        await db.query(
          'servicos',
          where: 'id = ? AND comercio_id = ?',
          whereArgs: ['servico_remoto_ok', comercioId],
        ),
        hasLength(1),
      );

      final agendamentos = await db.query(
        'agendamentos',
        where: 'id = ? AND comercio_id = ?',
        whereArgs: ['public_appointment_teste_sync', comercioId],
      );

      expect(agendamentos, hasLength(1));
      expect(agendamentos.single['cliente_id'], 'cliente_remoto_ok');
      expect(agendamentos.single['profissional_id'], 'profissional_remoto_ok');
      expect(agendamentos.single['servico_id'], 'servico_remoto_ok');
      expect(agendamentos.single['origem'], 'online');

      final config = await db.query(
        'integracoes_configuracao',
        where: 'comercio_id = ?',
        whereArgs: [comercioId],
        limit: 1,
      );

      expect(config.single['ultimo_cursor'], 5);

      final desconhecida = await db.query(
        'alteracoes_remotas',
        where: 'comercio_id = ? AND cursor = ?',
        whereArgs: [comercioId, 1],
        limit: 1,
      );

      expect(desconhecida, hasLength(1));
      expect(desconhecida.single['erro'], isNotNull);
    },
  );
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
    return {
      'changes': [
        {
          'cursor': 1,
          'entity': 'entidade_que_nao_existe',
          'entityId': 'ignorar_1',
          'serverVersion': 1,
          'deleted': false,
          'payload': {'id': 'ignorar_1'},
        },
        {
          'cursor': 2,
          'entity': 'clientes',
          'entityId': 'cliente_remoto_ok',
          'serverVersion': 1,
          'deleted': false,
          'payload': {
            'id': 'cliente_remoto_ok',
            'comercio_id': 'com_sync_unknown_test',
            'nome': 'Cliente remoto',
            'whatsapp': '11999998888',
            'ativo': 1,
            'data_cadastro': '2026-08-10T17:30:00.000Z',
            'total_atendimentos': 0,
            'total_gasto': 0.0,
            'pontos_fidelidade': 0,
          },
        },
        {
          'cursor': 3,
          'entity': 'profissionais',
          'entityId': 'profissional_remoto_ok',
          'serverVersion': 1,
          'deleted': false,
          'payload': {
            'id': 'profissional_remoto_ok',
            'comercio_id': 'com_sync_unknown_test',
            'nome': 'Rafa',
            'whatsapp': '11949965001',
            'cargo': 'Manicure',
            'ativo': 1,
            'percentual_comissao': 50.0,
            'meta_mensal': 0.0,
            'faturamento_mes': 0.0,
            'data_cadastro': '2026-08-10T17:30:00.000Z',
          },
        },
        {
          'cursor': 4,
          'entity': 'servicos',
          'entityId': 'servico_remoto_ok',
          'serverVersion': 1,
          'deleted': false,
          'payload': {
            'id': 'servico_remoto_ok',
            'comercio_id': 'com_sync_unknown_test',
            'nome': 'Mao',
            'categoria': 'Manicure',
            'preco': 40.0,
            'duracao_minutos': 60,
            'ativo': 1,
            'custo_estimado': 0.0,
            'data_cadastro': '2026-08-10T17:30:00.000Z',
          },
        },
        {
          'cursor': 5,
          'entity': 'agendamentos',
          'entityId': 'public_appointment_teste_sync',
          'serverVersion': 1,
          'deleted': false,
          'payload': {
            'id': 'public_appointment_teste_sync',
            'comercio_id': 'com_sync_unknown_test',
            'business_id': 'com_sync_unknown_test',
            'cliente_id': 'cliente_remoto_ok',
            'profissional_id': 'profissional_remoto_ok',
            'servico_id': 'servico_remoto_ok',
            'inicio': '2026-08-12T11:00:00.000Z',
            'fim': '2026-08-12T12:00:00.000Z',
            'status': 'agendado',
            'valor_servico': 40.0,
            'desconto': 0.0,
            'valor_recebido': 0.0,
            'confirmado': 0,
            'compareceu': 0,
            'observacoes': 'Teste sync publico',
            'data_criacao': '2026-08-10T17:30:00.000Z',
            'created_at': '2026-08-10T17:30:00.000Z',
            'updated_at': '2026-08-10T17:30:00.000Z',
            'origem': 'online',
          },
        },
      ],
      'nextCursor': 5,
    };
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
