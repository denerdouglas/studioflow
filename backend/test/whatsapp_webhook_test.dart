import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:studioflow_backend/studioflow_backend.dart';
import 'package:test/test.dart';

void main() {
  const secret = 'meta-app-secret-test';
  late MemoryMessageAutomationStore automations;
  late Handler handler;

  setUp(() async {
    automations = MemoryMessageAutomationStore();
    final config = BackendConfig.fromEnvironment({
      'DATABASE_URL': 'postgresql://unused/test',
      'JWT_SECRET':
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      'PUBLIC_BASE_URL': 'https://api.studioflow.test',
      'WHATSAPP_VERIFY_TOKEN': 'verify-test',
      'META_APP_SECRET': secret,
    });
    handler = StudioFlowApi(
      store: MemoryBackendStore(),
      automations: automations,
      config: config,
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
}
