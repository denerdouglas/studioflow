import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/models/domain/sincronizacao_backend.dart';
import 'package:studioflow/models/domain/acesso.dart';
import 'package:studioflow/repositories/agenda_completa_repository.dart';
import 'package:studioflow/repositories/agenda_repository.dart';
import 'package:studioflow/repositories/notification_center_repository.dart';
import 'package:studioflow/services/backend_api_client.dart';
import 'package:studioflow/services/backend_sync_service.dart';
import 'package:studioflow/services/backend_token_vault.dart';
import 'package:studioflow/services/session_controller.dart';

void main() {
  sqfliteFfiInit();

  test(
    'troca de serviço e preferência sobrevivem a sync e novo dispositivo',
    () async {
      const businessId = 'business-remote-proof';
      final remote = _StoreApi(businessId);
      Future<void> seed(
        String entity,
        String id,
        Map<String, Object?> payload,
      ) async => remote.seed(entity, id, {
        'id': id,
        'comercio_id': businessId,
        ...payload,
      });
      final now = DateTime.utc(2026, 9, 5).toIso8601String();
      await seed('clientes', 'c1', {
        'nome': 'Ana',
        'whatsapp': '',
        'data_cadastro': now,
      });
      await seed('profissionais', 'p1', {
        'nome': 'Rafa',
        'whatsapp': '',
        'cargo': 'Manicure',
        'data_cadastro': now,
      });
      await seed('servicos', 'mao', {
        'nome': 'Mão',
        'categoria': 'Unhas',
        'preco': 25.0,
        'duracao_minutos': 30,
        'data_cadastro': now,
      });
      await seed('servicos', 'pe_mao', {
        'nome': 'Pé e Mão',
        'categoria': 'Unhas',
        'preco': 50.0,
        'duracao_minutos': 30,
        'data_cadastro': now,
      });
      await seed('agendamentos', 'a1', {
        'cliente_id': 'c1',
        'profissional_id': 'p1',
        'servico_id': 'mao',
        'inicio': '2026-09-08T10:00:00.000',
        'fim': '2026-09-08T10:30:00.000',
        'valor_servico': 25.0,
        'status': 'agendado',
        'data_criacao': now,
        'created_at': now,
        'updated_at': now,
      });
      final api = remote;
      final first = await _device(businessId);
      addTearDown(first.close);
      final vault = _Vault(_session(businessId));
      final sync = BackendSyncService(
        databaseProvider: () async => first,
        api: api,
        vault: vault,
      );
      await sync.sincronizar(businessId);
      SessionController.instance.entrar(
        UsuarioAcesso(
          id: 'owner',
          comercioId: businessId,
          codigoComercio: 'REMOTE',
          nomeComercio: 'Studio Remote',
          nomeExibicao: 'Studio Remote',
          nome: 'Dona',
          telefone: '11999999999',
          emailLogin: 'remote@test.dev',
          funcao: FuncaoUsuario.dono,
          ativo: true,
          permissoes: permissoesPadrao(FuncaoUsuario.dono),
          acoes: acoesPadrao(FuncaoUsuario.dono),
        ),
      );
      addTearDown(SessionController.instance.cancelarSincronizacaoEmTeste);

      await AgendaCompletaRepository(
        databaseProvider: () async => first,
        comercioId: businessId,
        usuarioId: 'owner',
      ).atualizarCompleto(
        AgendamentoRegistro(
          id: 'a1',
          clienteId: 'c1',
          clienteNome: 'Ana',
          profissionalId: 'p1',
          profissionalNome: 'Rafa',
          servicoId: 'pe_mao',
          servicoNome: 'Pé e Mão',
          inicio: DateTime(2026, 9, 8, 10),
          fim: DateTime(2026, 9, 8, 10, 30),
          status: 'agendado',
          valorServico: 50,
          desconto: 0,
          valorRecebido: 0,
          confirmado: false,
          compareceu: false,
          dataCriacao: DateTime.parse(now),
        ),
      );
      await NotificationCenterRepository(
        databaseProvider: () async => first,
        businessId: businessId,
        gateway: _NoNotifications(),
      ).setEnabled('agenda', 'whatsapp', false);
      await sync.sincronizar(businessId);

      final second = await _device(businessId);
      addTearDown(second.close);
      final reload = BackendSyncService(
        databaseProvider: () async => second,
        api: api,
        vault: _Vault(_session(businessId)),
      );
      await reload.sincronizar(businessId);
      final appointment = (await second.query(
        'agendamentos',
        where: 'id = ?',
        whereArgs: ['a1'],
      )).single;
      expect(appointment['servico_id'], 'pe_mao');
      expect(appointment['valor_servico'], 50.0);
      expect(appointment['fim'], '2026-09-08T10:30:00.000');
      final preference = (await second.query(
        'notification_preferences',
        where: 'business_id = ?',
        whereArgs: [businessId],
      )).single;
      expect(preference['enabled'], 0);
    },
  );
}

Future<Database> _device(String businessId) async {
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 47,
      singleInstance: false,
      onCreate: DatabaseSchemaLatest.criar,
    ),
  );
  final now = DateTime.now().toUtc().toIso8601String();
  await db.insert('comercios', {
    'id': businessId,
    'codigo_acesso': 'REMOTE',
    'nome': 'Studio Remote',
    'nome_exibicao': 'Studio Remote',
    'responsavel': 'Dona',
    'telefone': '11999999999',
    'email': 'remote@test.dev',
    'ativo': 1,
    'criado_em': now,
    'atualizado_em': now,
  });
  await db.insert('integracoes_configuracao', {
    'comercio_id': businessId,
    'provedor_backend': 'studioflow_rest',
    'endpoint_publico': 'https://api.test',
    'sincronizacao_ativa': 1,
    'ultimo_cursor': 0,
    'atualizado_em': now,
  });
  return db;
}

SessaoBackend _session(String id) => SessaoBackend(
  comercioId: id,
  usuarioId: 'owner',
  accessToken: 'access',
  refreshToken: 'refresh',
  refreshExpiraEm: DateTime.now().add(const Duration(days: 1)),
);

class _StoreApi extends BackendApiClient {
  final String businessId;
  final Map<String, Map<String, Object?>> records = {};
  final Map<String, int> versions = {};
  final List<Map<String, Object?>> changes = [];
  _StoreApi(this.businessId);
  void seed(String entity, String id, Map<String, Object?> payload) =>
      _save(entity, id, payload);
  void _save(String entity, String id, Map<String, Object?> payload) {
    final key = '$entity::$id';
    final version = (versions[key] ?? 0) + 1;
    versions[key] = version;
    records[key] = Map<String, Object?>.from(payload);
    changes.add({
      'cursor': changes.length + 1,
      'entity': entity,
      'entityId': id,
      'serverVersion': version,
      'deleted': false,
      'payload': payload,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  @override
  Future<Map<String, dynamic>> push({
    required Uri endpoint,
    required String accessToken,
    required List<Map<String, Object?>> operations,
  }) async {
    final results = <Map<String, Object?>>[];
    for (final item in operations) {
      final entity = item['entity']! as String,
          id = item['entityId']! as String;
      final key = '$entity::$id';
      final expected = versions[key] ?? 0;
      final supplied = (item['localVersion'] as num?)?.toInt() ?? 0;
      if (supplied != expected) {
        results.add({
          'operationId': item['operationId'],
          'status': 'conflict',
          'serverVersion': expected,
          'serverPayload': records[key],
        });
        continue;
      }
      _save(entity, id, Map<String, Object?>.from(item['payload'] as Map));
      results.add({
        'operationId': item['operationId'],
        'status': 'applied',
        'serverVersion': versions[key],
        'serverPayload': records[key],
      });
    }
    return {'results': results};
  }

  @override
  Future<Map<String, dynamic>> pull({
    required Uri endpoint,
    required String accessToken,
    required int cursor,
    int limit = 200,
  }) async {
    final page = changes
        .where((item) => (item['cursor'] as int) > cursor)
        .take(limit)
        .toList();
    return {
      'changes': page,
      'nextCursor': page.isEmpty ? cursor : page.last['cursor'],
    };
  }
}

class _Vault implements BackendTokenVault {
  SessaoBackend? value;
  _Vault(this.value);
  @override
  Future<SessaoBackend?> read(String comercioId) async => value;
  @override
  Future<void> write(SessaoBackend session) async => value = session;
  @override
  Future<void> delete(String comercioId) async => value = null;
}

class _NoNotifications implements LocalNotificationGateway {
  @override
  Future<void> cancel(int id) async {}
  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime date,
    String? payload,
    required String category,
  }) async {}
}
