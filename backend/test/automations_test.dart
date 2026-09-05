import 'package:studioflow_backend/studioflow_backend.dart';
import 'package:test/test.dart';

void main() {
  test('agenda dois lembretes e aniversários sem duplicar', () async {
    final store = MemoryMessageAutomationStore();
    _seedBusiness(store, 'salao-a');
    final sender = _FakeSender();
    final engine = MessageAutomationEngine(
      store: store,
      sender: sender,
      publicBaseUrl: Uri.parse('https://studioflow.test'),
    );
    final now = DateTime.utc(2026, 7, 29, 15);

    expect(await engine.schedule(now), 4);
    expect(await engine.schedule(now), 0);
    final history = await store.history('salao-a');
    expect(
      history.map((m) => m.kind),
      containsAll({
        'appointment_day_before',
        'appointment_two_hours',
        'birthday_owner',
        'birthday_client',
      }),
    );
    expect(
      history
          .where((m) => m.kind.startsWith('appointment'))
          .every(
            (m) =>
                m.body.contains('Cliente Ana') &&
                m.body.contains('Profissional Bia') &&
                m.body.contains('Corte'),
          ),
      isTrue,
    );
  });

  test('processa 16h, 2h e 08h/09h sem depender do aplicativo', () async {
    final store = MemoryMessageAutomationStore();
    _seedBusiness(store, 'salao-a');
    final sender = _FakeSender();
    final engine = MessageAutomationEngine(
      store: store,
      sender: sender,
      publicBaseUrl: Uri.parse('https://studioflow.test'),
    );
    await engine.schedule(DateTime.utc(2026, 7, 29, 3));

    var result = await engine.dispatch(DateTime.utc(2026, 7, 29, 19));
    expect(result.$1, 3);
    expect(result.$2, 0);
    result = await engine.dispatch(DateTime.utc(2026, 7, 30, 15));
    expect(result.$1, 1);
    expect(sender.sent, hasLength(4));
  });

  test('16h usa o offset do negócio e não um UTC fixo', () async {
    final store = MemoryMessageAutomationStore();
    _seedBusiness(store, 'salao-a');
    final business = store.sources.firstWhere(
      (item) => item.entity == 'comercios',
    );
    store.sources.remove(business);
    store.sources.add(
      AutomationSourceRecord(
        businessId: business.businessId,
        entity: business.entity,
        entityId: business.entityId,
        payload: {...business.payload, 'timezone_offset_minutes': -240},
      ),
    );
    final engine = MessageAutomationEngine(
      store: store,
      sender: _FakeSender(),
      publicBaseUrl: Uri.parse('https://studioflow.test'),
    );
    await engine.schedule(DateTime.utc(2026, 7, 29, 3));
    final confirmation = (await store.history(
      'salao-a',
    )).singleWhere((message) => message.kind == 'appointment_day_before');
    expect(confirmation.scheduledAt, DateTime.utc(2026, 7, 29, 20));
  });

  test('falha registra tentativa e agenda retentativa', () async {
    final store = MemoryMessageAutomationStore();
    _seedBusiness(store, 'salao-a');
    final sender = _FakeSender(fail: true);
    final engine = MessageAutomationEngine(
      store: store,
      sender: sender,
      publicBaseUrl: Uri.parse('https://studioflow.test'),
    );
    await engine.schedule(DateTime.utc(2026, 7, 29, 3));
    final result = await engine.dispatch(DateTime.utc(2026, 7, 29, 19));
    expect(result.$2, 3);
    final retried = (await store.history(
      'salao-a',
    )).where((m) => m.status == 'retry');
    expect(retried, hasLength(3));
    expect(retried.every((m) => m.attempts == 1), isTrue);
    expect(retried.every((m) => m.lastError!.contains('indisponível')), isTrue);
  });

  test('status de entrega atualiza histórico completo', () async {
    final store = MemoryMessageAutomationStore();
    _seedBusiness(store, 'salao-a');
    final sender = _FakeSender();
    final engine = MessageAutomationEngine(
      store: store,
      sender: sender,
      publicBaseUrl: Uri.parse('https://studioflow.test'),
    );
    await engine.schedule(DateTime.utc(2026, 7, 29, 3));
    await engine.dispatch(DateTime.utc(2026, 7, 29, 19));
    final sent = (await store.history(
      'salao-a',
    )).firstWhere((m) => m.status == 'sent');
    await store.updateDelivery(
      externalId: sent.externalId!,
      status: 'delivered',
    );
    expect(
      (await store.history(
        'salao-a',
      )).firstWhere((m) => m.id == sent.id).status,
      'delivered',
    );
  });

  test('três salões permanecem isolados', () async {
    final store = MemoryMessageAutomationStore();
    for (final id in ['salao-a', 'salao-b', 'salao-c']) {
      _seedBusiness(store, id);
    }
    final engine = MessageAutomationEngine(
      store: store,
      sender: _FakeSender(),
      publicBaseUrl: Uri.parse('https://studioflow.test'),
    );
    expect(await engine.schedule(DateTime.utc(2026, 7, 29, 3)), 12);
    for (final id in ['salao-a', 'salao-b', 'salao-c']) {
      final history = await store.history(id);
      expect(history, hasLength(4));
      expect(history.every((m) => m.businessId == id), isTrue);
    }
  });

  test('aniversário da cliente nunca é enviado duas vezes no ano', () async {
    final store = MemoryMessageAutomationStore();
    _seedBusiness(store, 'salao-a');
    final engine = MessageAutomationEngine(
      store: store,
      sender: _FakeSender(),
      publicBaseUrl: Uri.parse('https://studioflow.test'),
    );
    await engine.schedule(DateTime.utc(2026, 7, 29, 3));
    await engine.schedule(DateTime.utc(2026, 7, 29, 20));
    final birthdays = (await store.history(
      'salao-a',
    )).where((m) => m.kind == 'birthday_client');
    expect(birthdays, hasLength(1));
  });

  test('cancelamento sincronizado remove lembretes ainda pendentes', () async {
    final store = MemoryMessageAutomationStore();
    _seedBusiness(store, 'salao-a');
    final engine = MessageAutomationEngine(
      store: store,
      sender: _FakeSender(),
      publicBaseUrl: Uri.parse('https://studioflow.test'),
    );
    await engine.schedule(DateTime.utc(2026, 7, 29, 3));
    final appointment = store.sources.firstWhere(
      (item) => item.entity == 'agendamentos',
    );
    store.sources.remove(appointment);
    store.sources.add(
      AutomationSourceRecord(
        businessId: appointment.businessId,
        entity: appointment.entity,
        entityId: appointment.entityId,
        payload: {...appointment.payload, 'status': 'cancelado'},
      ),
    );
    await engine.schedule(DateTime.utc(2026, 7, 29, 4));
    final reminders = (await store.history(
      'salao-a',
    )).where((message) => message.appointmentId == appointment.entityId);
    expect(reminders, hasLength(2));
    expect(reminders.every((message) => message.status == 'cancelled'), isTrue);
  });

  test(
    'não agenda mensagens para cliente sem consentimento WhatsApp',
    () async {
      final store = MemoryMessageAutomationStore();
      _seedBusiness(store, 'salao-a');
      final client = store.sources.firstWhere(
        (item) => item.entity == 'clientes',
      );
      store.sources.remove(client);
      store.sources.add(
        AutomationSourceRecord(
          businessId: client.businessId,
          entity: client.entity,
          entityId: client.entityId,
          payload: {...client.payload, 'consentimento_whatsapp': 0},
        ),
      );
      final engine = MessageAutomationEngine(
        store: store,
        sender: _FakeSender(),
        publicBaseUrl: Uri.parse('https://studioflow.test'),
      );
      expect(await engine.schedule(DateTime.utc(2026, 7, 29, 3)), 0);
    },
  );

  test('preferência desativa somente a categoria escolhida', () async {
    final store = MemoryMessageAutomationStore();
    _seedBusiness(store, 'salao-a');
    store.sources.add(
      const AutomationSourceRecord(
        businessId: 'salao-a',
        entity: 'notification_preferences',
        entityId: 'appointment_day_before:whatsapp',
        payload: {
          'category': 'appointment_day_before',
          'channel': 'whatsapp',
          'enabled': false,
        },
      ),
    );
    final engine = MessageAutomationEngine(
      store: store,
      sender: _FakeSender(),
      publicBaseUrl: Uri.parse('https://studioflow.test'),
    );

    await engine.schedule(DateTime.utc(2026, 7, 29, 3));

    final kinds = (await store.history('salao-a')).map((item) => item.kind);
    expect(kinds, isNot(contains('appointment_day_before')));
    expect(kinds, contains('appointment_two_hours'));
  });
}

void _seedBusiness(MemoryMessageAutomationStore store, String businessId) {
  store.sources.addAll([
    AutomationSourceRecord(
      businessId: businessId,
      entity: 'comercios',
      entityId: businessId,
      payload: {
        'id': businessId,
        'nome': 'Studio $businessId',
        'nome_exibicao': 'Studio $businessId',
        'telefone': '5511999990000',
        'endereco': 'Rua Principal, 100',
      },
    ),
    AutomationSourceRecord(
      businessId: businessId,
      entity: 'clientes',
      entityId: 'cliente-$businessId',
      payload: {
        'id': 'cliente-$businessId',
        'nome': 'Cliente Ana',
        'whatsapp': '5511988880000',
        'data_nascimento': '1990-07-29T00:00:00.000',
        'data_cadastro': '2020-01-01T00:00:00.000',
        'total_gasto': 2500,
        'ativo': 1,
        'consentimento_whatsapp': 1,
      },
    ),
    AutomationSourceRecord(
      businessId: businessId,
      entity: 'profissionais',
      entityId: 'pro-$businessId',
      payload: {'id': 'pro-$businessId', 'nome': 'Profissional Bia'},
    ),
    AutomationSourceRecord(
      businessId: businessId,
      entity: 'servicos',
      entityId: 'servico-$businessId',
      payload: {'id': 'servico-$businessId', 'nome': 'Corte'},
    ),
    AutomationSourceRecord(
      businessId: businessId,
      entity: 'agendamentos',
      entityId: 'agenda-$businessId',
      payload: {
        'id': 'agenda-$businessId',
        'cliente_id': 'cliente-$businessId',
        'profissional_id': 'pro-$businessId',
        'servico_id': 'servico-$businessId',
        'inicio': '2026-07-30T14:00:00.000',
        'status': 'agendado',
      },
    ),
  ]);
}

final class _FakeSender implements AutomationMessageSender {
  final bool fail;
  final List<OutboundMessage> sent = [];

  _FakeSender({this.fail = false});

  @override
  bool get configured => true;

  @override
  Future<String> send(OutboundMessage message) async {
    if (fail) throw StateError('Provedor indisponível');
    sent.add(message);
    return 'external-${message.id}';
  }
}
