import 'package:studioflow_backend/studioflow_backend.dart';
import 'package:test/test.dart';

void main() {
  group('WhatsApp conversacional determinístico', () {
    late _Fixture f;
    setUp(() async => f = await _Fixture.create());

    test(
      '1 consulta amanhã para pé e mão oferece somente slots reais',
      () async {
        await f.send('Tem horário amanhã para pé e mão?');
        expect(await f.lastReply, contains('10:00'));
        expect(await f.lastReply, isNot(contains('11:00')));
      },
    );

    test('2 serviço inexistente não é inventado', () async {
      await f.send('Tem horário amanhã para massagem lunar?');
      expect(await f.lastReply, contains('Não encontrei esse serviço'));
    });

    test('3 serviço ambíguo solicita escolha real', () async {
      await f.send('Quero marcar unha amanhã');
      expect(await f.lastReply, contains('Qual você deseja'));
    });

    test('4 profissional específico é respeitado', () async {
      await f.send('Tem horário amanhã para pé e mão com Rafa?');
      expect(await f.lastReply, contains('10:00'));
      final state = await f.state();
      expect((state['context'] as Map)['professional_id'], 'p-rafa');
    });

    test('5 profissional indisponível não produz horário', () async {
      await f.send('Tem horário amanhã para pé e mão com Bia?');
      expect(await f.lastReply, contains('Não encontrei horários livres'));
    });

    test('6 escolha de horário pede confirmação', () async {
      await f.send('Tem horário amanhã para pé e mão com Rafa?');
      await f.send('10h');
      expect(await f.replies, contains(contains('Responda SIM para agendar')));
    });

    test('7 confirmação cria agendamento com dados reais', () async {
      await f.book();
      final rows = await f.booking.publicSchedulingRecords(
        businessId: 'business-a',
        entities: const {'agendamentos'},
      );
      expect(rows.where((item) => item['origem'] == 'whatsapp'), hasLength(1));
      expect(rows.last['servico_id'], 's-pe-mao');
      expect(rows.last['profissional_id'], 'p-rafa');
    });

    test('8 mensagem duplicada não cria agendamento duplicado', () async {
      await f.book(confirmId: 'same-confirm');
      await f.send('SIM', id: 'same-confirm');
      final rows = await f.booking.publicSchedulingRecords(
        businessId: 'business-a',
        entities: const {'agendamentos'},
      );
      expect(rows.where((item) => item['origem'] == 'whatsapp'), hasLength(1));
    });

    test('9 horário ocupado entre oferta e confirmação é recusado', () async {
      await f.send('Tem horário amanhã para pé e mão com Rafa?');
      await f.send('10h');
      await f.insertAppointment(
        'other',
        'client-other',
        '2026-09-06T10:00:00.000',
        '2026-09-06T10:30:00.000',
      );
      await f.send('SIM');
      expect(await f.replies, contains(contains('acabou de ser ocupado')));
    });

    test(
      '10 remarcação atualiza horário e cancela mensagens antigas',
      () async {
        await f.insertAppointment(
          'a1',
          'client-a',
          '2026-09-06T09:00:00.000',
          '2026-09-06T09:30:00.000',
        );
        await f.queueReminder('a1');
        await f.send('Quero mudar meu horário');
        await f.send('amanhã');
        await f.send('10h');
        await f.send('SIM');
        final appointment = await f.latest('agendamentos', 'a1');
        expect(appointment.payload['inicio'], startsWith('2026-09-06T10:00'));
        expect(
          (await f.messages.history('business-a'))
              .where((m) => m.appointmentId == 'a1')
              .any((item) => item.status == 'cancelled'),
          isTrue,
        );
      },
    );

    test('11 remarcação ambígua não escolhe agendamento', () async {
      await f.insertAppointment(
        'a1',
        'client-a',
        '2026-09-06T09:00:00.000',
        '2026-09-06T09:30:00.000',
      );
      await f.insertAppointment(
        'a2',
        'client-a',
        '2026-09-07T09:00:00.000',
        '2026-09-07T09:30:00.000',
      );
      await f.send('Quero remarcar');
      expect(await f.lastReply, contains('mais de um horário'));
    });

    test('12 cancelamento confirmado altera status', () async {
      await f.insertAppointment(
        'a1',
        'client-a',
        '2026-09-06T09:00:00.000',
        '2026-09-06T09:30:00.000',
      );
      await f.send('Quero cancelar');
      await f.send('SIM');
      expect(
        (await f.latest('agendamentos', 'a1')).payload['status'],
        'cancelado',
      );
    });

    test('13 frase ambígua exige confirmação e não cancela', () async {
      await f.insertAppointment(
        'a1',
        'client-a',
        '2026-09-06T09:00:00.000',
        '2026-09-06T09:30:00.000',
      );
      await f.send('Acho que não vou conseguir ir');
      expect(await f.lastReply, contains('SIM PARA CANCELAR'));
      expect(
        (await f.latest('agendamentos', 'a1')).payload['status'],
        'agendado',
      );
    });

    test('14 SIM no estado de cancelamento cancela', () async {
      await f.insertAppointment(
        'a1',
        'client-a',
        '2026-09-06T09:00:00.000',
        '2026-09-06T09:30:00.000',
      );
      await f.send('Acho que não vou conseguir ir');
      await f.send('sim');
      expect(
        (await f.latest('agendamentos', 'a1')).payload['status'],
        'cancelado',
      );
    });

    test(
      '15 SIM sem estado fica disponível para confirmação de presença',
      () async {
        expect(await f.send('SIM'), isFalse);
      },
    );

    test('16 sessão expirada não executa ação antiga', () async {
      await f.send('Tem horário amanhã para pé e mão com Rafa?');
      await f.expireState();
      expect(await f.send('10h'), isFalse);
      expect(
        (await f.booking.publicSchedulingRecords(
          businessId: 'business-a',
          entities: const {'agendamentos'},
        )),
        isEmpty,
      );
    });

    test('17 Business A não consulta agenda Business B', () async {
      await f.send('Tem horário amanhã para pé e mão?', receiver: '111');
      final state = await f.state();
      expect(state['business_id'], 'business-a');
    });

    test('18 telefone igual em dois negócios usa número receptor', () async {
      await f.addSecondBusinessSamePhone();
      await f.send('Tem horário amanhã para pé e mão?', receiver: '111');
      expect((await f.state())['business_id'], 'business-a');
    });
  });
}

class _Fixture {
  final MemoryBackendStore backend;
  final MemoryMessageAutomationStore messages;
  late final WhatsAppConversationEngine engine;
  int sequence = 0;
  _Fixture(this.backend, this.messages) {
    engine = WhatsAppConversationEngine(
      store: backend,
      booking: backend,
      messages: messages,
    );
  }
  PublicBookingStore get booking => backend;
  Future<String> get lastReply async => (await messages.history(
    'business-a',
  )).firstWhere((item) => item.kind == 'whatsapp_conversation_reply').body;
  Future<List<String>> get replies async =>
      (await messages.history('business-a'))
          .where((item) => item.kind == 'whatsapp_conversation_reply')
          .map((item) => item.body)
          .toList();

  static Future<_Fixture> create() async {
    final backend = MemoryBackendStore();
    final messages = MemoryMessageAutomationStore();
    final fixture = _Fixture(backend, messages);
    messages.sources.addAll([
      const AutomationSourceRecord(
        businessId: 'business-a',
        entity: 'comercios',
        entityId: 'business-a',
        payload: {
          'nome': 'Studio A',
          'phone_number_id': '111',
          'timezone_offset_minutes': -180,
        },
      ),
      const AutomationSourceRecord(
        businessId: 'business-a',
        entity: 'clientes',
        entityId: 'client-a',
        payload: {'nome': 'Ana', 'whatsapp': '5511999990000'},
      ),
    ]);
    await fixture.seed('servicos', 's-mao', {
      'nome': 'Mão',
      'preco': 20,
      'duracao_minutos': 30,
      'ativo': 1,
    });
    await fixture.seed('servicos', 's-pe-mao', {
      'nome': 'Pé e Mão',
      'preco': 40,
      'duracao_minutos': 30,
      'ativo': 1,
    });
    await fixture.seed('servicos', 's-unha-gel', {
      'nome': 'Unha em gel',
      'preco': 60,
      'duracao_minutos': 60,
      'ativo': 1,
    });
    await fixture.seed('servicos', 's-unha-tradicional', {
      'nome': 'Unha tradicional',
      'preco': 30,
      'duracao_minutos': 30,
      'ativo': 1,
    });
    await fixture.seed('profissionais', 'p-rafa', {'nome': 'Rafa', 'ativo': 1});
    await fixture.seed('profissionais', 'p-bia', {'nome': 'Bia', 'ativo': 1});
    await fixture.seed('profissional_servicos', 'ps1', {
      'profissional_id': 'p-rafa',
      'servico_id': 's-pe-mao',
    });
    await fixture.seed('profissional_servicos', 'ps2', {
      'profissional_id': 'p-bia',
      'servico_id': 's-pe-mao',
    });
    await fixture.seed('horarios_profissionais', 'h1', {
      'profissional_id': 'p-rafa',
      'dia_semana': 7,
      'inicio': '10:00',
      'fim': '11:00',
    });
    return fixture;
  }

  Future<bool> send(String text, {String? id, String receiver = '111'}) =>
      engine.process(
        WhatsAppInbound(
          messageId: id ?? 'in-${sequence++}',
          from: '5511999990000',
          receiver: receiver,
          text: text,
          receivedAt: DateTime.utc(2026, 9, 5, 15),
        ),
      );
  Future<void> book({String? confirmId}) async {
    await send('Tem horário amanhã para pé e mão com Rafa?');
    await send('10h');
    await send('SIM', id: confirmId);
  }

  Future<void> seed(
    String entity,
    String id,
    Map<String, Object?> payload, {
    String business = 'business-a',
  }) async {
    await backend.applyMutations(
      actor: AuthContext(
        userId: 'owner',
        businessId: business,
        role: 'dono',
        sessionId: 's',
      ),
      mutations: [
        SyncMutation(
          operationId: 'seed-$business-$entity-$id',
          entity: entity,
          entityId: id,
          operation: 'criar',
          localVersion: 0,
          payload: {'id': id, 'comercio_id': business, ...payload},
        ),
      ],
    );
  }

  Future<void> insertAppointment(
    String id,
    String client,
    String start,
    String end,
  ) => seed('agendamentos', id, {
    'cliente_id': client,
    'profissional_id': 'p-rafa',
    'servico_id': 's-pe-mao',
    'inicio': start,
    'fim': end,
    'status': 'agendado',
  });
  Future<SyncChange> latest(String entity, String id) async =>
      (await backend.pullChanges(
        businessId: 'business-a',
        afterCursor: 0,
        limit: 1000,
      )).where((e) => e.entity == entity && e.entityId == id).last;
  Future<Map<String, Object?>> state() async => (await backend.pullChanges(
    businessId: 'business-a',
    afterCursor: 0,
    limit: 1000,
  )).where((e) => e.entity == 'whatsapp_conversations').last.payload;
  Future<void> expireState() async {
    final s = await latest(
      'whatsapp_conversations',
      (await backend.pullChanges(
        businessId: 'business-a',
        afterCursor: 0,
        limit: 1000,
      )).where((e) => e.entity == 'whatsapp_conversations').last.entityId,
    );
    await backend.applyMutations(
      actor: const AuthContext(
        userId: 'x',
        businessId: 'business-a',
        role: 'dono',
        sessionId: 'x',
      ),
      mutations: [
        SyncMutation(
          operationId: 'expire',
          entity: 'whatsapp_conversations',
          entityId: s.entityId,
          operation: 'atualizar',
          localVersion: s.serverVersion,
          payload: {...s.payload, 'expires_at': '2026-09-05T14:00:00.000Z'},
        ),
      ],
    );
  }

  Future<void> queueReminder(String appointment) => messages.enqueue(
    OutboundMessage(
      id: 'rem-$appointment',
      businessId: 'business-a',
      kind: 'appointment_day_before',
      dedupeKey: 'rem-$appointment',
      channel: 'whatsapp',
      destination: '5511999990000',
      body: 'lembrete',
      scheduledAt: DateTime.utc(2026, 9, 5),
      status: 'queued',
      attempts: 0,
      appointmentId: appointment,
    ),
  );
  Future<void> addSecondBusinessSamePhone() async {
    messages.sources.addAll([
      const AutomationSourceRecord(
        businessId: 'business-b',
        entity: 'comercios',
        entityId: 'business-b',
        payload: {'nome': 'Studio B', 'phone_number_id': '222'},
      ),
      const AutomationSourceRecord(
        businessId: 'business-b',
        entity: 'clientes',
        entityId: 'client-b',
        payload: {'nome': 'Ana B', 'whatsapp': '5511999990000'},
      ),
    ]);
  }
}
