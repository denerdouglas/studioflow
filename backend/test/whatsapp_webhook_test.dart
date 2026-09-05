import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:studioflow_backend/studioflow_backend.dart';
import 'package:studioflow_backend/src/academy_memory_store.dart';
import 'package:test/test.dart';

void main() {
  const secret = 'meta-app-secret-test';
  late MemoryMessageAutomationStore automations;
  late MemoryBackendStore backendStore;
  late Handler handler;

  setUp(() async {
    automations = MemoryMessageAutomationStore();
    backendStore = MemoryBackendStore();
    final config = BackendConfig.fromEnvironment({
      'DATABASE_URL': 'postgresql://unused/test',
      'JWT_SECRET':
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      'PUBLIC_BASE_URL': 'https://api.studioflow.test',
      'WHATSAPP_VERIFY_TOKEN': 'verify-test',
      'META_APP_SECRET': secret,
    });
    handler = StudioFlowApi(
      store: backendStore,
      marketplace: MarketplaceService(backendStore),
      adminService: MarketplaceAdminService(backendStore),
      automations: automations,
      config: config,
      academy: AcademyService(AcademyMemoryStore()),
      secureRedirect: SecureRedirectService(AcademyMemoryStore()),
    ).handler;
    await automations.enqueue(
      OutboundMessage(
        id: 'message-1',
        businessId: 'business-1',
        kind: 'appointment_two_hours',
        dedupeKey: 'dedupe-1',
        channel: 'whatsapp',
        destination: '5511999999999',
        body: 'Lembrete',
        scheduledAt: DateTime.now().toUtc(),
        status: 'queued',
        attempts: 0,
      ),
    );
    await automations.markSent(
      'message-1',
      externalId: 'wamid.test',
      sentAt: DateTime.now().toUtc(),
    );
  });

  test('Meta valida o webhook e atualiza status real assinado', () async {
    final verification = await handler(
      Request(
        'GET',
        Uri.parse(
          'http://localhost/v1/webhooks/whatsapp?hub.mode=subscribe&hub.verify_token=verify-test&hub.challenge=12345',
        ),
      ),
    );
    expect(verification.statusCode, 200);
    expect(await verification.readAsString(), '12345');

    final body = jsonEncode({
      'entry': [
        {
          'changes': [
            {
              'value': {
                'statuses': [
                  {'id': 'wamid.test', 'status': 'delivered'},
                ],
              },
            },
          ],
        },
      ],
    });
    final signature = Hmac(
      sha256,
      utf8.encode(secret),
    ).convert(utf8.encode(body));
    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/v1/webhooks/whatsapp'),
        headers: {
          'content-type': 'application/json',
          'x-hub-signature-256': 'sha256=$signature',
        },
        body: body,
      ),
    );
    expect(response.statusCode, 204);
    expect(
      (await automations.history('business-1')).single.status,
      'delivered',
    );
  });

  test('webhook rejeita assinatura inválida', () async {
    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/v1/webhooks/whatsapp'),
        headers: {'x-hub-signature-256': 'sha256=invalid'},
        body: '{}',
      ),
    );
    expect(response.statusCode, 401);
  });

  test('SIM confirma uma vez somente quando associação é inequívoca', () async {
    automations.sources.add(
      const AutomationSourceRecord(
        businessId: 'business-1',
        entity: 'clientes',
        entityId: 'client-1',
        payload: {'whatsapp': '551188887777'},
      ),
    );
    await backendStore.applyMutations(
      actor: const AuthContext(
        userId: 'owner-1',
        businessId: 'business-1',
        role: 'dono',
        sessionId: 'session-1',
      ),
      mutations: const [
        SyncMutation(
          operationId: 'create-appointment',
          entity: 'agendamentos',
          entityId: 'appointment-1',
          operation: 'criar',
          localVersion: 0,
          payload: {'id': 'appointment-1', 'confirmado': 0},
        ),
      ],
    );
    await automations.enqueue(
      OutboundMessage(
        id: 'confirmation-1',
        businessId: 'business-1',
        kind: 'appointment_day_before',
        dedupeKey: 'appointment:appointment-1:day_before',
        channel: 'whatsapp',
        destination: '551188887777',
        body: 'Confirme',
        scheduledAt: DateTime.now().toUtc(),
        status: 'sent',
        attempts: 1,
        appointmentId: 'appointment-1',
        clientId: 'client-1',
      ),
    );

    Future<void> send(String id, String text) async {
      final body = jsonEncode({
        'entry': [
          {
            'changes': [
              {
                'value': {
                  'messages': [
                    {
                      'id': id,
                      'from': '551188887777',
                      'text': {'body': text},
                    },
                  ],
                },
              },
            ],
          },
        ],
      });
      final signature = Hmac(
        sha256,
        utf8.encode(secret),
      ).convert(utf8.encode(body));
      final response = await handler(
        Request(
          'POST',
          Uri.parse('http://localhost/v1/webhooks/whatsapp'),
          headers: {'x-hub-signature-256': 'sha256=$signature'},
          body: body,
        ),
      );
      expect(response.statusCode, 204);
    }

    await send('wamid.confirm-1', 'Sim');
    await send('wamid.confirm-1-duplicate', 'CONFIRMO');
    final changes = await backendStore.pullChanges(
      businessId: 'business-1',
      afterCursor: 0,
      limit: 20,
    );
    final appointmentChanges = changes
        .where((item) => item.entityId == 'appointment-1')
        .toList();
    expect(appointmentChanges, hasLength(2));
    expect(appointmentChanges.last.payload['confirmado'], 1);
    expect(appointmentChanges.last.payload['confirmado_via'], 'whatsapp');
  });
}
