import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:studioflow_backend/studioflow_backend.dart';
import 'package:studioflow_backend/src/academy_memory_store.dart';
import 'package:test/test.dart';

void main() {
  const jwtSecret =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
  late MemoryBackendStore store;
  late MemoryMessageAutomationStore automations;
  late Handler handler;

  setUp(() {
    store = MemoryBackendStore();
    automations = MemoryMessageAutomationStore();
    final config = BackendConfig.fromEnvironment({
      'DATABASE_URL': 'postgresql://unused/test',
      'JWT_SECRET': jwtSecret,
      'PUBLIC_BASE_URL': 'https://api.studioflow.test',
    });
    handler = StudioFlowApi(
      store: store,
      marketplace: MarketplaceService(store),
      adminService: MarketplaceAdminService(store),
      automations: automations,
      config: config,
      academy: AcademyService(AcademyMemoryStore()),
      secureRedirect: SecureRedirectService(AcademyMemoryStore()),
    ).handler;
  });

  test('mesmo login em dois estabelecimentos exige seleção', () async {
    final first = await _register(handler, 'Studio A');
    final second = await _register(handler, 'Studio B');

    final selection = await _call(handler, 'POST', '/v1/auth/login', {
      'login': 'DONA@STUDIO.TEST',
      'password': 'senha-segura',
    });
    expect(selection.status, 200);
    expect(selection.json['selectionRequired'], isTrue);
    expect(selection.json['accounts'], hasLength(2));

    final selected = await _call(handler, 'POST', '/v1/auth/login', {
      'login': 'dona@studio.test',
      'password': 'senha-segura',
      'businessId': (second.json['account'] as Map)['businessId'],
    });
    expect(selected.status, 200);
    expect((selected.json['account'] as Map)['businessName'], 'Studio B');
    expect(first.json['accessToken'], isNot(selected.json['accessToken']));
  });

  test('refresh token é rotativo e o anterior deixa de funcionar', () async {
    final registration = await _register(handler, 'Studio Refresh');
    final original = registration.json['refreshToken'] as String;
    final refreshed = await _call(handler, 'POST', '/v1/auth/refresh', {
      'refreshToken': original,
    });
    expect(refreshed.status, 200);
    expect(refreshed.json['refreshToken'], isNot(original));

    final replay = await _call(handler, 'POST', '/v1/auth/refresh', {
      'refreshToken': original,
    });
    expect(replay.status, 401);
    expect((replay.json['error'] as Map)['code'], 'invalid_refresh_token');
  });

  test(
    'sincronização é idempotente, detecta conflito e isola empresas',
    () async {
      final first = await _register(handler, 'Studio Sync A');
      final second = await _register(handler, 'Studio Sync B');
      final tokenA = first.json['accessToken'] as String;
      final tokenB = second.json['accessToken'] as String;
      final operation = {
        'operationId': 'op-1',
        'entity': 'clientes',
        'entityId': 'cliente-1',
        'operation': 'criar',
        'localVersion': 0,
        'payload': {'nome': 'Cliente A'},
      };

      final push = await _call(handler, 'POST', '/v1/sync/push', {
        'operations': [operation],
      }, token: tokenA);
      expect(push.status, 200);
      expect(
        ((push.json['results'] as List).single as Map)['status'],
        'applied',
      );

      final retry = await _call(handler, 'POST', '/v1/sync/push', {
        'operations': [operation],
      }, token: tokenA);
      expect(
        ((retry.json['results'] as List).single as Map)['serverVersion'],
        1,
      );

      final conflict = await _call(handler, 'POST', '/v1/sync/push', {
        'operations': [
          {
            ...operation,
            'operationId': 'op-2',
            'operation': 'atualizar',
            'localVersion': 0,
          },
        ],
      }, token: tokenA);
      expect(
        ((conflict.json['results'] as List).single as Map)['status'],
        'conflict',
      );

      final pullA = await _call(
        handler,
        'GET',
        '/v1/sync/pull?cursor=0',
        null,
        token: tokenA,
      );
      final pullB = await _call(
        handler,
        'GET',
        '/v1/sync/pull?cursor=0',
        null,
        token: tokenB,
      );
      expect(pullA.json['changes'], hasLength(1));
      expect(pullB.json['changes'], isEmpty);
    },
  );

  test('serviço externo ausente retorna mensagem clara', () async {
    final response = await _call(handler, 'POST', '/v1/auth/password/request', {
      'login': 'dona@studio.test',
      'channel': 'email',
    });
    expect(response.status, 503);
    expect((response.json['error'] as Map)['code'], 'provider_not_configured');
  });

  test('push de cancelamento interrompe mensagens imediatamente', () async {
    final registered = await _register(handler, 'Studio Cancelamento');
    final account = registered.json['account'] as Map;
    final token = registered.json['accessToken'] as String;
    await automations.enqueue(
      OutboundMessage(
        id: 'message-cancel',
        businessId: account['businessId'] as String,
        kind: 'appointment_two_hours',
        dedupeKey: 'appointment:agenda-1:two-hours',
        channel: 'whatsapp',
        destination: '5511999999999',
        body: 'Lembrete',
        scheduledAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        status: 'queued',
        attempts: 0,
        appointmentId: 'agenda-1',
      ),
    );
    final response = await _call(handler, 'POST', '/v1/sync/push', {
      'operations': [
        {
          'operationId': 'op-cancel-1',
          'entity': 'agendamentos',
          'entityId': 'agenda-1',
          'operation': 'atualizar',
          'localVersion': 0,
          'payload': {
            'id': 'agenda-1',
            'comercio_id': account['businessId'],
            'status': 'cancelado',
            'cancelamento_motivo': 'Cliente solicitou',
          },
        },
      ],
    }, token: token);
    expect(response.status, 200);
    expect(
      (await automations.history(
        account['businessId'] as String,
      )).single.status,
      'cancelled',
    );
  });
}

Future<_ApiResponse> _register(Handler handler, String businessName) {
  return _call(handler, 'POST', '/v1/auth/register-business', {
    'businessName': businessName,
    'ownerName': 'Dona Studio',
    'phone': '5511999999999',
    'login': 'dona@studio.test',
    'password': 'senha-segura',
    'segment': 'salao',
  });
}

Future<_ApiResponse> _call(
  Handler handler,
  String method,
  String path,
  Map<String, Object?>? body, {
  String? token,
}) async {
  final response = await handler(
    Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: {
        if (body != null) 'content-type': 'application/json',
        if (token != null) 'authorization': 'Bearer $token',
      },
      body: body == null ? null : jsonEncode(body),
    ),
  );
  final content = await response.readAsString();
  return _ApiResponse(
    response.statusCode,
    content.isEmpty
        ? const <String, Object?>{}
        : Map<String, dynamic>.from(jsonDecode(content) as Map),
  );
}

final class _ApiResponse {
  final int status;
  final Map<String, dynamic> json;

  const _ApiResponse(this.status, this.json);
}
