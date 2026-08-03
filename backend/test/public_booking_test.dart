import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:studioflow_backend/studioflow_backend.dart';
import 'package:studioflow_backend/src/academy_memory_store.dart';
import 'package:test/test.dart';

void main() {
  late MemoryBackendStore store;
  late Handler handler;

  setUp(() {
    store = MemoryBackendStore();
    final config = BackendConfig.fromEnvironment({
      'DATABASE_URL': 'postgresql://unused/test',
      'JWT_SECRET':
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      'PUBLIC_BASE_URL': 'https://api.studioflow.test',
    });
    handler = StudioFlowApi(
      store: store,
      marketplace: MarketplaceService(store),
      adminService: MarketplaceAdminService(store),
      academy: AcademyService(AcademyMemoryStore()),
      secureRedirect: SecureRedirectService(AcademyMemoryStore()),
      config: config,
    ).handler;
  });

  test('cadastro gera slug normalizado, exclusivo e não reservado', () async {
    final first = await _register(handler, 'Rafa Rodrigues Beauty');
    final second = await _register(
      handler,
      'Rafa Rodrigues Beauty',
      login: 'outra@studio.test',
    );
    final firstBooking = await store.ensurePublicBooking(
      businessId: (first['account'] as Map)['businessId'] as String,
      businessName: 'Rafa Rodrigues Beauty',
    );
    expect(firstBooking.slug, 'rafa-rodrigues-beauty');
    expect(
      (await store.findPublicBooking('rafa-rodrigues-beauty'))?.businessId,
      (first['account'] as Map)['businessId'],
    );
    expect(
      (await store.findPublicBooking('rafa-rodrigues-beauty-2'))?.businessId,
      (second['account'] as Map)['businessId'],
    );
    final reserved = await store.ensurePublicBooking(
      businessId: 'business-reserved',
      businessName: 'Admin',
    );
    expect(reserved.slug, isNot('admin'));
  });

  test(
    'página pública isola dados, cria de forma idempotente e bloqueia conflito',
    () async {
      final registered = await _register(handler, 'Studio P\u00fablico');
      final account = registered['account'] as Map;
      final booking = await store.ensurePublicBooking(
        businessId: account['businessId'] as String,
        businessName: 'Studio P\u00fablico',
      );
      expect(booking.slug, 'studio-publico');
      final businessId = account['businessId'] as String;
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final start = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9);
      await store.applyMutations(
        actor: AuthContext(
          userId: account['userId'] as String,
          businessId: businessId,
          role: 'dono',
          sessionId: 'test',
        ),
        mutations: [
          SyncMutation(
            operationId: 'service-1',
            entity: 'servicos',
            entityId: 'service-1',
            operation: 'criar',
            localVersion: 0,
            payload: {
              'id': 'service-1',
              'nome': 'Pé e mão',
              'preco': 80,
              'duracao_minutos': 60,
              'ativo': true,
            },
          ),
          const SyncMutation(
            operationId: 'professional-1',
            entity: 'profissionais',
            entityId: 'professional-1',
            operation: 'criar',
            localVersion: 0,
            payload: {'id': 'professional-1', 'nome': 'Rafa', 'ativo': true},
          ),
          SyncMutation(
            operationId: 'schedule-1',
            entity: 'horarios_profissionais',
            entityId: 'schedule-1',
            operation: 'criar',
            localVersion: 0,
            payload: {
              'id': 'schedule-1',
              'profissional_id': 'professional-1',
              'dia_semana': start.weekday,
              'hora_inicio': '08:00',
              'hora_fim': '18:00',
            },
          ),
        ],
      );
      final page = await _call(
        handler,
        'GET',
        '/v1/public/booking/studio-publico',
      );
      expect(page.statusCode, 200);
      final services = await _call(
        handler,
        'GET',
        '/v1/public/booking/studio-publico/services',
      );
      expect(
        (jsonDecode(await services.readAsString()) as Map)['results'],
        hasLength(1),
      );
      final body = {
        'serviceId': 'service-1',

        'professionalId': 'professional-1',
        'name': 'Maria',
        'phone': '5511999999999',
        'startsAt': start.toIso8601String(),
        'endsAt': start.add(const Duration(hours: 1)).toIso8601String(),
      };
      final created = await _call(
        handler,
        'POST',
        '/v1/public/booking/studio-publico/appointments',
        body: body,
        headers: {'idempotency-key': 'booking-test-1'},
      );
      expect(created.statusCode, 201);
      final payload = jsonDecode(await created.readAsString()) as Map;
      expect(payload['token'], isNotEmpty);
      final changes = await store.pullChanges(
        businessId: businessId,
        afterCursor: 0,
        limit: 100,
      );
      expect(
        changes.where((change) => change.entity == 'clientes'),
        hasLength(1),
      );
      final appointments = changes
          .where((change) => change.entity == 'agendamentos')
          .toList();
      expect(appointments, hasLength(1));
      expect(appointments.single.payload['origem'], 'agendamento_publico');
      expect(appointments.single.payload['profissional_id'], 'professional-1');
      final token = payload['token'] as String;
      final confirmed = await _call(
        handler,
        'POST',
        '/v1/public/appointments/$token/confirm',
      );
      expect(confirmed.statusCode, 200);
      final afterConfirm = await store.pullChanges(
        businessId: businessId,
        afterCursor: 0,
        limit: 100,
      );
      expect(
        afterConfirm
            .lastWhere((change) => change.entity == 'agendamentos')
            .payload['status'],
        'confirmado',
      );
      final retry = await _call(
        handler,
        'POST',
        '/v1/public/booking/studio-publico/appointments',
        body: body,
        headers: {'idempotency-key': 'booking-test-1'},
      );
      expect(retry.statusCode, 201);
      final conflict = await _call(
        handler,
        'POST',
        '/v1/public/booking/studio-publico/appointments',
        body: body,
        headers: {'idempotency-key': 'booking-test-2'},
      );
      expect(conflict.statusCode, 409);
    },
  );
}

Future<Map<String, dynamic>> _register(
  Handler handler,
  String name, {
  String login = 'dona@studio.test',
}) async {
  final response = await _call(
    handler,
    'POST',
    '/v1/auth/register-business',
    body: {
      'businessName': name,
      'ownerName': 'Dona',
      'phone': '5511999999999',
      'login': login,
      'password': 'senha-segura',
    },
  );
  return Map<String, dynamic>.from(
    jsonDecode(await response.readAsString()) as Map,
  );
}

Future<Response> _call(
  Handler handler,
  String method,
  String path, {
  Map<String, Object?>? body,
  Map<String, String>? headers,
}) async {
  return await handler(
    Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: {
        if (body != null) 'content-type': 'application/json',
        ...?headers,
      },
      body: body == null ? null : jsonEncode(body),
    ),
  );
}
