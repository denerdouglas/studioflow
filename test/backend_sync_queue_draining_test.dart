import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/models/domain/sincronizacao_backend.dart';
import 'package:studioflow/services/backend_api_client.dart';
import 'package:studioflow/services/backend_sync_service.dart';
import 'package:studioflow/services/backend_token_vault.dart';

void main() {
  sqfliteFfiInit();

  test('drenagem de fila longa com isolamento de falha 400', () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 37,
        onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
        onCreate: DatabaseSchemaLatest.criar,
      ),
    );
    addTearDown(db.close);

    final now = DateTime.now().toUtc().toIso8601String();
    const comercioId = 'com_sync_drain_test';

    await db.insert('comercios', {
      'id': comercioId,
      'codigo_acesso': 'SYNCDRAIN',
      'nome': 'Studio Sync Drain',
      'nome_exibicao': 'Studio Sync Drain',
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

    for (int i = 1; i <= 153; i++) {
      await db.insert('clientes', {
        'id': 'cliente_$i',
        'comercio_id': comercioId,
        'nome': 'Cliente $i',
        'whatsapp': '11999999999',
        'ativo': 1,
        'data_cadastro': now,
        'total_atendimentos': 0,
        'total_gasto': 0,
        'pontos_fidelidade': 0,
      });

      await db.insert('fila_sincronizacao', {
        'id': 'sync_teste_$i',
        'comercio_id': comercioId,
        'entidade': 'clientes',
        'entidade_id': 'cliente_$i',
        'operacao': 'CREATE',
        'payload_json': jsonEncode({'id': 'cliente_$i', 'nome': 'Cliente $i'}),
        'status': 'pendente',
        'tentativas': 0,
        'versao_local': 0,
        'versao_servidor': 0,
        'criada_em': now,
        'atualizada_em': now,
      });
    }

    final vault = _MemoryVault(
      SessaoBackend(
        comercioId: comercioId,
        usuarioId: 'user_sync_drain',
        accessToken: 'access',
        refreshToken: 'refresh',
        refreshExpiraEm: DateTime.now().toUtc().add(const Duration(days: 1)),
      ),
    );

    final fakeApi = _FakeApiDrain(invalidId: 'cliente_51');

    final service = BackendSyncService(
      databaseProvider: () async => db,
      api: fakeApi,
      vault: vault,
    );

    // Chamada 1
    var result = await service.sincronizar(comercioId);
    expect(result.enviadas, 152); // 152 passam, 1 falha e fica pendente

    // Chamada 2
    await db.update('fila_sincronizacao', {'proxima_tentativa': null});
    result = await service.sincronizar(comercioId);
    expect(result.enviadas, 0); // O item falha de novo

    // Chamada 3
    await db.update('fila_sincronizacao', {'proxima_tentativa': null});
    result = await service.sincronizar(comercioId);
    expect(result.enviadas, 0); // O item falha pela 3a vez e vai para erro

    // Verifica a fila local
    final filaPendente = await db.query(
      'fila_sincronizacao',
      where: 'comercio_id = ? AND status = ?',
      whereArgs: [comercioId, 'pendente'],
    );
    expect(
      filaPendente,
      isEmpty,
      reason: 'Nenhum item deve ficar pendente após 3 erros',
    );

    final filaErro = await db.query(
      'fila_sincronizacao',
      where: 'comercio_id = ? AND status = ?',
      whereArgs: [comercioId, 'erro'],
    );
    expect(filaErro, hasLength(1), reason: 'Apenas um item deve ter falhado');

    // Verifica se as chaves foram mantidas e status='erro'
    final erroRecord = filaErro.single;
    expect(erroRecord['entidade_id'], 'cliente_51');
    expect(erroRecord['entidade'], 'clientes');
    expect(erroRecord['operacao'], 'criar');
    expect(erroRecord['ultimo_erro'], 'Lote contem item invalido');
    expect(erroRecord['tentativas'], 3);
  });
}

class _FakeApiDrain extends BackendApiClient {
  final String invalidId;

  _FakeApiDrain({required this.invalidId});

  @override
  Future<Map<String, dynamic>> push({
    required Uri endpoint,
    required String accessToken,
    required List<Map<String, Object?>> operations,
  }) async {
    // Se no lote atual houver o 'invalidId', retornamos HTTP 400 para todo o lote.
    final temInvalido = operations.any((op) {
      final payload = op['payload'] as Map;
      return payload['id'] == invalidId;
    });

    if (temInvalido) {
      throw const BackendHttpException(
        400,
        'bad_request',
        'Lote contem item invalido',
      );
    }

    return {
      'results': [
        for (final op in operations)
          {
            'operationId': op['operationId'],
            'status': 'applied',
            'serverVersion': 1,
            'serverPayload': op['payload'],
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
    return {'changes': [], 'nextCursor': cursor};
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
