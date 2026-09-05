import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import 'automations.dart';
import 'models.dart';
import 'public_booking.dart';
import 'store.dart';

enum WhatsAppConversationState {
  idle,
  bookingWaitingService,
  bookingWaitingDate,
  bookingWaitingSlot,
  bookingWaitingConfirmation,
  rescheduleWaitingAppointment,
  rescheduleWaitingDate,
  rescheduleWaitingSlot,
  rescheduleWaitingConfirmation,
  cancelWaitingAppointment,
  cancelWaitingConfirmation,
}

final class WhatsAppInbound {
  final String messageId;
  final String from;
  final String? receiver;
  final String text;
  final DateTime receivedAt;
  const WhatsAppInbound({
    required this.messageId,
    required this.from,
    required this.text,
    required this.receivedAt,
    this.receiver,
  });
}

final class WhatsAppConversationEngine {
  static const _ttl = Duration(minutes: 30);
  final BackendStore store;
  final PublicBookingStore booking;
  final MessageAutomationStore messages;
  final Uuid uuid;

  WhatsAppConversationEngine({
    required this.store,
    required this.booking,
    required this.messages,
    this.uuid = const Uuid(),
  });

  Future<bool> process(WhatsAppInbound inbound) async {
    final sources = await messages.sourceRecords();
    final businessId = _resolveBusiness(sources, inbound);
    if (businessId == null) return false;
    final phone = _digits(inbound.from);
    final client = sources.where((item) {
      if (item.businessId != businessId || item.entity != 'clientes') {
        return false;
      }
      return _digits(
            (item.payload['whatsapp'] ?? item.payload['telefone'])?.toString(),
          ) ==
          phone;
    }).firstOrNull;
    if (client == null) {
      await _reply(
        businessId,
        phone,
        inbound.messageId,
        'Não encontrei seu cadastro neste estabelecimento.',
      );
      return true;
    }
    final id = sha256.convert(utf8.encode('$businessId:$phone')).toString();
    var state = await _loadState(businessId, id);
    if (state != null &&
        DateTime.parse(
          state['expires_at']!.toString(),
        ).isBefore(inbound.receivedAt.toUtc())) {
      await _clearState(businessId, id, state);
      state = null;
    }
    if (state?['state'] == WhatsAppConversationState.idle.name) state = null;
    final normalized = _normalize(inbound.text);
    if (state != null) {
      return _continue(
        inbound,
        businessId,
        phone,
        client,
        id,
        state,
        normalized,
      );
    }
    if (_isCancelIntent(normalized)) {
      return _beginCancel(inbound, businessId, phone, client, id);
    }
    if (_isRescheduleIntent(normalized)) {
      return _beginReschedule(inbound, businessId, phone, client, id);
    }
    if (_isAppointmentQuery(normalized)) {
      final appointments = await _eligibleAppointments(
        businessId,
        client.entityId,
        inbound.receivedAt,
      );
      await _reply(
        businessId,
        phone,
        inbound.messageId,
        appointments.isEmpty
            ? 'Você não possui horário futuro agendado.'
            : appointments
                  .map((item) {
                    final start = DateTime.parse(
                      item.payload['inicio']!.toString(),
                    );
                    return 'Seu horário é ${_displayDate(start)} às ${_displayTime(start)}.';
                  })
                  .join('\n'),
      );
      return true;
    }
    if (_isBookingIntent(normalized)) {
      return _beginBooking(inbound, businessId, phone, client, id, normalized);
    }
    return false;
  }

  String? _resolveBusiness(
    List<AutomationSourceRecord> sources,
    WhatsAppInbound inbound,
  ) {
    final receiver = _digits(inbound.receiver);
    final businesses = sources.where((item) {
      if (item.entity != 'comercios') return false;
      if (receiver.isEmpty) return true;
      return {
        _digits(item.payload['whatsapp_phone_number_id']?.toString()),
        _digits(item.payload['phone_number_id']?.toString()),
        _digits(item.payload['whatsapp']?.toString()),
        _digits(item.payload['telefone']?.toString()),
      }.contains(receiver);
    }).toList();
    if (businesses.length == 1) return businesses.single.businessId;
    final phone = _digits(inbound.from);
    final clientBusinesses = sources
        .where(
          (item) =>
              item.entity == 'clientes' &&
              _digits(
                    (item.payload['whatsapp'] ?? item.payload['telefone'])
                        ?.toString(),
                  ) ==
                  phone,
        )
        .map((item) => item.businessId)
        .toSet();
    return clientBusinesses.length == 1 ? clientBusinesses.single : null;
  }

  Future<bool> _beginBooking(
    WhatsAppInbound inbound,
    String businessId,
    String phone,
    AutomationSourceRecord client,
    String stateId,
    String text,
  ) async {
    final services = await booking.publicEntities(
      businessId: businessId,
      entity: 'servicos',
    );
    final matches = _matchesByName(services, text);
    if (matches.isEmpty) {
      await _reply(
        businessId,
        phone,
        inbound.messageId,
        'Não encontrei esse serviço. Consulte o estabelecimento.',
      );
      return true;
    }
    if (matches.length > 1) {
      await _saveState(
        businessId,
        stateId,
        WhatsAppConversationState.bookingWaitingService,
        {'client_id': client.entityId},
      );
      await _reply(
        businessId,
        phone,
        inbound.messageId,
        'Temos:\n${matches.map((item) => '• ${item['nome']}').join('\n')}\nQual você deseja?',
      );
      return true;
    }
    final context = <String, Object?>{
      'client_id': client.entityId,
      'service_id': matches.single['id'],
      'service_name': matches.single['nome'],
      'price': matches.single['preco'],
      'duration': matches.single['duracao_minutos'],
    };
    final date = _parseDate(
      text,
      inbound.receivedAt,
      _offset(sources: await messages.sourceRecords(), businessId: businessId),
    );
    if (date == null) {
      await _saveState(
        businessId,
        stateId,
        WhatsAppConversationState.bookingWaitingDate,
        context,
      );
      await _reply(
        businessId,
        phone,
        inbound.messageId,
        'Para qual dia você deseja agendar?',
      );
      return true;
    }
    context['date'] = date.toIso8601String();
    final requestedProfessional = await _professionalFromText(businessId, text);
    if (requestedProfessional != null) {
      context['professional_id'] = requestedProfessional['id'];
    }
    return _offerSlots(inbound, businessId, phone, stateId, context, false);
  }

  Future<bool> _continue(
    WhatsAppInbound inbound,
    String businessId,
    String phone,
    AutomationSourceRecord client,
    String stateId,
    Map<String, Object?> state,
    String text,
  ) async {
    final current = WhatsAppConversationState.values.byName(
      state['state']!.toString(),
    );
    final context = Map<String, Object?>.from(state['context'] as Map);
    if (current == WhatsAppConversationState.cancelWaitingConfirmation) {
      if (_yes(text)) {
        return _executeCancel(
          inbound,
          businessId,
          phone,
          stateId,
          state,
          context,
        );
      }
      if (_no(text)) {
        await _clearState(businessId, stateId, state);
        await _reply(
          businessId,
          phone,
          inbound.messageId,
          'Seu horário foi mantido.',
        );
      }
      return true;
    }
    if (current == WhatsAppConversationState.bookingWaitingService) {
      final services = await booking.publicEntities(
        businessId: businessId,
        entity: 'servicos',
      );
      final matches = _matchesByName(services, text);
      if (matches.length != 1) {
        await _reply(
          businessId,
          phone,
          inbound.messageId,
          'Escolha um dos serviços informados.',
        );
        return true;
      }
      context.addAll({
        'service_id': matches.single['id'],
        'service_name': matches.single['nome'],
        'price': matches.single['preco'],
        'duration': matches.single['duracao_minutos'],
      });
      await _saveState(
        businessId,
        stateId,
        WhatsAppConversationState.bookingWaitingDate,
        context,
        previous: state,
      );
      await _reply(
        businessId,
        phone,
        inbound.messageId,
        'Para qual dia você deseja agendar?',
      );
      return true;
    }
    if (current == WhatsAppConversationState.bookingWaitingDate ||
        current == WhatsAppConversationState.rescheduleWaitingDate) {
      final date = _parseDate(
        text,
        inbound.receivedAt,
        _offset(
          sources: await messages.sourceRecords(),
          businessId: businessId,
        ),
      );
      if (date == null) {
        await _reply(
          businessId,
          phone,
          inbound.messageId,
          'Não entendi a data. Informe hoje, amanhã ou um dia da semana.',
        );
        return true;
      }
      context['date'] = date.toIso8601String();
      return _offerSlots(
        inbound,
        businessId,
        phone,
        stateId,
        context,
        current == WhatsAppConversationState.rescheduleWaitingDate,
        previous: state,
      );
    }
    if (current == WhatsAppConversationState.bookingWaitingSlot ||
        current == WhatsAppConversationState.rescheduleWaitingSlot) {
      final chosen = _chooseSlot(text, (context['slots'] as List).cast<Map>());
      if (chosen == null) {
        await _reply(
          businessId,
          phone,
          inbound.messageId,
          'Escolha um dos horários oferecidos.',
        );
        return true;
      }
      context.addAll({
        'start': chosen['start'],
        'professional_id': chosen['professional_id'],
      });
      final reschedule =
          current == WhatsAppConversationState.rescheduleWaitingSlot;
      await _saveState(
        businessId,
        stateId,
        reschedule
            ? WhatsAppConversationState.rescheduleWaitingConfirmation
            : WhatsAppConversationState.bookingWaitingConfirmation,
        context,
        previous: state,
      );
      await _reply(
        businessId,
        phone,
        inbound.messageId,
        'Confirmando: ${context['service_name']} em ${_displayDate(DateTime.parse(chosen['start'].toString()))} às ${_displayTime(DateTime.parse(chosen['start'].toString()))}. Responda SIM para ${reschedule ? 'remarcar' : 'agendar'}.',
      );
      return true;
    }
    if (current == WhatsAppConversationState.bookingWaitingConfirmation &&
        _yes(text)) {
      return _executeBooking(
        inbound,
        businessId,
        phone,
        client,
        stateId,
        state,
        context,
      );
    }
    if (current == WhatsAppConversationState.rescheduleWaitingConfirmation &&
        _yes(text)) {
      return _executeReschedule(
        inbound,
        businessId,
        phone,
        stateId,
        state,
        context,
      );
    }
    return true;
  }

  Future<bool> _offerSlots(
    WhatsAppInbound inbound,
    String businessId,
    String phone,
    String stateId,
    Map<String, Object?> context,
    bool reschedule, {
    Map<String, Object?>? previous,
  }) async {
    final slots = await _availableSlots(businessId, context);
    if (slots.isEmpty) {
      await _reply(
        businessId,
        phone,
        inbound.messageId,
        'Não encontrei horários livres nessa data.',
      );
      return true;
    }
    context['slots'] = slots.take(8).toList();
    await _saveState(
      businessId,
      stateId,
      reschedule
          ? WhatsAppConversationState.rescheduleWaitingSlot
          : WhatsAppConversationState.bookingWaitingSlot,
      context,
      previous: previous,
    );
    await _reply(
      businessId,
      phone,
      inbound.messageId,
      'Tenho estes horários disponíveis:\n${slots.take(8).map((item) => _displayTime(DateTime.parse(item['start'].toString()))).join('\n')}\nQual você prefere?',
    );
    return true;
  }

  Future<List<Map<String, Object?>>> _availableSlots(
    String businessId,
    Map<String, Object?> context,
  ) async {
    final date = DateTime.parse(context['date']!.toString());
    final serviceId = context['service_id']!.toString();
    final duration = (context['duration'] as num).toInt();
    final rows = await booking.publicSchedulingRecords(
      businessId: businessId,
      entities: const {
        'profissionais',
        'profissional_servicos',
        'horarios_profissionais',
        'agendamentos',
        'bloqueios_agenda',
        'folgas_profissionais',
        'ferias_profissionais',
      },
    );
    final requested = context['professional_id']?.toString();
    final professionals = rows
        .where(
          (row) =>
              row['_entity'] == 'profissionais' &&
              row['ativo'] != 0 &&
              row['ativo'] != false &&
              (requested == null || row['id'].toString() == requested),
        )
        .where((pro) {
          final links = rows.where(
            (link) =>
                link['_entity'] == 'profissional_servicos' &&
                link['profissional_id'] == pro['id'],
          );
          return links.isEmpty ||
              links.any((link) => link['servico_id'].toString() == serviceId);
        });
    final result = <Map<String, Object?>>[];
    for (final pro in professionals) {
      final works = rows.where(
        (row) =>
            row['_entity'] == 'horarios_profissionais' &&
            row['profissional_id'] == pro['id'] &&
            (row['dia_semana'] as num?)?.toInt() == date.weekday,
      );
      for (final work in works) {
        final open = _clock(date, work['inicio'] ?? work['hora_inicio']);
        final close = _clock(date, work['fim'] ?? work['hora_fim']);
        final pauseStart = _clock(date, work['intervalo_inicio']);
        final pauseEnd = _clock(date, work['intervalo_fim']);
        if (open == null || close == null) continue;
        for (
          var slot = open;
          !slot.add(Duration(minutes: duration)).isAfter(close);
          slot = slot.add(const Duration(minutes: 15))
        ) {
          final end = slot.add(Duration(minutes: duration));
          if (pauseStart != null &&
              pauseEnd != null &&
              slot.isBefore(pauseEnd) &&
              end.isAfter(pauseStart)) {
            continue;
          }
          final busy = rows.any((row) {
            if (!const {
              'agendamentos',
              'bloqueios_agenda',
              'folgas_profissionais',
              'ferias_profissionais',
            }.contains(row['_entity'])) {
              return false;
            }
            if (row['profissional_id'] != null &&
                row['profissional_id'] != pro['id']) {
              return false;
            }
            if (row['_entity'] == 'agendamentos' &&
                (row['status'] == 'cancelado' || row['excluido'] == 1)) {
              return false;
            }
            final a = DateTime.tryParse(
              (row['inicio'] ?? row['data_inicio'] ?? '').toString(),
            );
            final b = DateTime.tryParse(
              (row['fim'] ?? row['data_fim'] ?? '').toString(),
            );
            return a != null && b != null && slot.isBefore(b) && end.isAfter(a);
          });
          if (!busy) {
            result.add({
              'start': slot.toIso8601String(),
              'professional_id': pro['id'],
            });
          }
        }
      }
    }
    result.sort(
      (a, b) => a['start'].toString().compareTo(b['start'].toString()),
    );
    return result;
  }

  Future<bool> _executeBooking(
    WhatsAppInbound inbound,
    String businessId,
    String phone,
    AutomationSourceRecord client,
    String stateId,
    Map<String, Object?> state,
    Map<String, Object?> context,
  ) async {
    final start = DateTime.parse(context['start']!.toString());
    final available = await _availableSlots(businessId, context);
    if (!available.any(
      (item) =>
          item['start'] == context['start'] &&
          item['professional_id'] == context['professional_id'],
    )) {
      await _saveState(
        businessId,
        stateId,
        WhatsAppConversationState.bookingWaitingSlot,
        context,
        previous: state,
      );
      await _reply(
        businessId,
        phone,
        inbound.messageId,
        'Esse horário acabou de ser ocupado. Posso te mostrar outros?',
      );
      return true;
    }
    try {
      await booking.createPublicAppointment(
        businessId: businessId,
        idempotencyKey: 'whatsapp:${inbound.messageId}',
        tokenHash: sha256
            .convert(utf8.encode('$businessId:${inbound.messageId}'))
            .toString(),
        publicToken: uuid.v4().replaceAll('-', ''),
        serviceId: context['service_id']!.toString(),
        professionalId: context['professional_id']!.toString(),
        clientName: client.payload['nome']?.toString() ?? 'Cliente',
        clientPhone: phone,
        notes: 'Agendado via WhatsApp',
        startsAt: start,
        endsAt: start.add(
          Duration(minutes: (context['duration'] as num).toInt()),
        ),
      );
      final createdRows = await booking.publicSchedulingRecords(
        businessId: businessId,
        entities: const {'agendamentos'},
      );
      final created = createdRows
          .where(
            (item) =>
                item['servico_id']?.toString() == context['service_id'] &&
                item['profissional_id']?.toString() ==
                    context['professional_id'] &&
                item['inicio']?.toString() == start.toIso8601String(),
          )
          .lastOrNull;
      if (created != null) {
        final appointmentId = created['id']!.toString();
        final remote = await _latest(businessId, 'agendamentos', appointmentId);
        if (remote != null) {
          await store.applyMutations(
            actor: AuthContext(
              userId: 'whatsapp:$phone',
              businessId: businessId,
              role: 'automation',
              sessionId: inbound.messageId,
              actorType: 'whatsapp_webhook',
            ),
            mutations: [
              SyncMutation(
                operationId: 'whatsapp_booking_${inbound.messageId}',
                entity: 'agendamentos',
                entityId: appointmentId,
                operation: 'atualizar',
                localVersion: remote.serverVersion,
                payload: {
                  ...remote.payload,
                  'origem': 'whatsapp',
                  'valor_servico': context['price'],
                },
              ),
            ],
          );
        }
        await _scheduleAppointmentMessages(
          businessId: businessId,
          phone: phone,
          clientId: client.entityId,
          appointmentId: appointmentId,
          start: start,
          serviceName: context['service_name']!.toString(),
        );
      }
      await _clearState(businessId, stateId, state);
      await _reply(
        businessId,
        phone,
        inbound.messageId,
        'Agendamento confirmado com sucesso.',
      );
    } on StateError {
      await _reply(
        businessId,
        phone,
        inbound.messageId,
        'Esse horário acabou de ser ocupado. Posso te mostrar outros?',
      );
    }
    return true;
  }

  Future<bool> _beginCancel(
    WhatsAppInbound inbound,
    String businessId,
    String phone,
    AutomationSourceRecord client,
    String stateId,
  ) async {
    final appointments = await _eligibleAppointments(
      businessId,
      client.entityId,
      inbound.receivedAt,
    );
    if (appointments.length != 1) {
      await _reply(
        businessId,
        phone,
        inbound.messageId,
        appointments.isEmpty
            ? 'Não encontrei horário futuro para cancelar.'
            : 'Você possui mais de um horário. Informe a data e hora que deseja cancelar.',
      );
      return true;
    }
    final item = appointments.single;
    await _saveState(
      businessId,
      stateId,
      WhatsAppConversationState.cancelWaitingConfirmation,
      {
        'appointment_id': item.entityId,
        'appointment_version': item.serverVersion,
      },
    );
    await _reply(
      businessId,
      phone,
      inbound.messageId,
      'Você deseja cancelar seu horário de ${_displayDate(DateTime.parse(item.payload['inicio'].toString()))} às ${_displayTime(DateTime.parse(item.payload['inicio'].toString()))}? Responda SIM PARA CANCELAR ou NÃO para manter.',
    );
    return true;
  }

  Future<bool> _executeCancel(
    WhatsAppInbound inbound,
    String businessId,
    String phone,
    String stateId,
    Map<String, Object?> state,
    Map<String, Object?> context,
  ) async {
    final current = await _latest(
      businessId,
      'agendamentos',
      context['appointment_id']!.toString(),
    );
    if (current != null && current.payload['status'] != 'cancelado') {
      await store.applyMutations(
        actor: AuthContext(
          userId: 'whatsapp:$phone',
          businessId: businessId,
          role: 'automation',
          sessionId: inbound.messageId,
          actorType: 'whatsapp_webhook',
        ),
        mutations: [
          SyncMutation(
            operationId: 'whatsapp_cancel_${inbound.messageId}',
            entity: 'agendamentos',
            entityId: current.entityId,
            operation: 'atualizar',
            localVersion: current.serverVersion,
            payload: {
              ...current.payload,
              'status': 'cancelado',
              'cancelamento_motivo': 'Cliente confirmou via WhatsApp',
            },
          ),
        ],
      );
      await messages.cancelAppointment(
        businessId: businessId,
        appointmentId: current.entityId,
        reason: 'Cancelado pelo cliente via WhatsApp.',
      );
    }
    await _clearState(businessId, stateId, state);
    await _reply(
      businessId,
      phone,
      inbound.messageId,
      'Seu horário foi cancelado.',
    );
    return true;
  }

  Future<bool> _beginReschedule(
    WhatsAppInbound inbound,
    String businessId,
    String phone,
    AutomationSourceRecord client,
    String stateId,
  ) async {
    final items = await _eligibleAppointments(
      businessId,
      client.entityId,
      inbound.receivedAt,
    );
    if (items.length != 1) {
      await _reply(
        businessId,
        phone,
        inbound.messageId,
        items.isEmpty
            ? 'Não encontrei horário futuro para remarcar.'
            : 'Você possui mais de um horário. Informe qual deseja remarcar.',
      );
      return true;
    }
    final item = items.single;
    final services = await booking.publicEntities(
      businessId: businessId,
      entity: 'servicos',
    );
    final service = services.firstWhere(
      (entry) => entry['id'] == item.payload['servico_id'],
    );
    await _saveState(
      businessId,
      stateId,
      WhatsAppConversationState.rescheduleWaitingDate,
      {
        'appointment_id': item.entityId,
        'service_id': service['id'],
        'service_name': service['nome'],
        'price': service['preco'],
        'duration': service['duracao_minutos'],
      },
    );
    await _reply(
      businessId,
      phone,
      inbound.messageId,
      'Para qual nova data você deseja remarcar?',
    );
    return true;
  }

  Future<bool> _executeReschedule(
    WhatsAppInbound inbound,
    String businessId,
    String phone,
    String stateId,
    Map<String, Object?> state,
    Map<String, Object?> context,
  ) async {
    final available = await _availableSlots(businessId, context);
    if (!available.any(
      (item) =>
          item['start'] == context['start'] &&
          item['professional_id'] == context['professional_id'],
    )) {
      await _reply(
        businessId,
        phone,
        inbound.messageId,
        'Esse horário acabou de ser ocupado. Posso te mostrar outros?',
      );
      return true;
    }
    final current = await _latest(
      businessId,
      'agendamentos',
      context['appointment_id']!.toString(),
    );
    if (current == null) return true;
    final start = DateTime.parse(context['start']!.toString());
    await store.applyMutations(
      actor: AuthContext(
        userId: 'whatsapp:$phone',
        businessId: businessId,
        role: 'automation',
        sessionId: inbound.messageId,
        actorType: 'whatsapp_webhook',
      ),
      mutations: [
        SyncMutation(
          operationId: 'whatsapp_reschedule_${inbound.messageId}',
          entity: 'agendamentos',
          entityId: current.entityId,
          operation: 'atualizar',
          localVersion: current.serverVersion,
          payload: {
            ...current.payload,
            'inicio': start.toIso8601String(),
            'fim': start
                .add(Duration(minutes: (context['duration'] as num).toInt()))
                .toIso8601String(),
            'profissional_id': context['professional_id'],
            'origem_alteracao': 'whatsapp',
          },
        ),
      ],
    );
    await messages.cancelAppointment(
      businessId: businessId,
      appointmentId: current.entityId,
      reason: 'Horário remarcado via WhatsApp.',
    );
    await _scheduleAppointmentMessages(
      businessId: businessId,
      phone: phone,
      clientId: current.payload['cliente_id']!.toString(),
      appointmentId: current.entityId,
      start: start,
      serviceName: context['service_name']!.toString(),
    );
    await _clearState(businessId, stateId, state);
    await _reply(
      businessId,
      phone,
      inbound.messageId,
      'Seu horário foi remarcado com sucesso.',
    );
    return true;
  }

  Future<List<SyncChange>> _eligibleAppointments(
    String businessId,
    String clientId,
    DateTime now,
  ) async => (await _entityRecords(businessId, 'agendamentos'))
      .where(
        (item) =>
            item.payload['cliente_id'] == clientId &&
            item.payload['status'] != 'cancelado' &&
            (DateTime.tryParse(
                  item.payload['inicio']?.toString() ?? '',
                )?.isAfter(now) ??
                false),
      )
      .toList();

  Future<SyncChange?> _latest(
    String businessId,
    String entity,
    String id,
  ) async => (await _entityRecords(
    businessId,
    entity,
  )).where((item) => item.entityId == id).firstOrNull;

  Future<List<SyncChange>> _entityRecords(
    String businessId,
    String entity,
  ) async {
    final all = await store.pullChanges(
      businessId: businessId,
      afterCursor: 0,
      limit: 10000,
    );
    final latest = <String, SyncChange>{};
    for (final item in all.where((item) => item.entity == entity)) {
      latest[item.entityId] = item;
    }
    return latest.values.where((item) => !item.deleted).toList();
  }

  Future<Map<String, Object?>?> _loadState(String businessId, String id) async {
    final item = await _latest(businessId, 'whatsapp_conversations', id);
    return item == null
        ? null
        : {...item.payload, '_version': item.serverVersion};
  }

  Future<void> _saveState(
    String businessId,
    String id,
    WhatsAppConversationState state,
    Map<String, Object?> context, {
    Map<String, Object?>? previous,
  }) async {
    final now = DateTime.now().toUtc();
    final persisted = previous == null
        ? await _latestIncludingDeleted(
            businessId,
            'whatsapp_conversations',
            id,
          )
        : null;
    final version =
        (previous?['_version'] as num?)?.toInt() ??
        persisted?.serverVersion ??
        0;
    await store.applyMutations(
      actor: AuthContext(
        userId: 'whatsapp',
        businessId: businessId,
        role: 'automation',
        sessionId: id,
        actorType: 'whatsapp_webhook',
      ),
      mutations: [
        SyncMutation(
          operationId: 'conversation_${uuid.v4()}',
          entity: 'whatsapp_conversations',
          entityId: id,
          operation: version == 0 ? 'criar' : 'atualizar',
          localVersion: version,
          payload: {
            'id': id,
            'business_id': businessId,
            'state': state.name,
            'intent': state.name.split('Waiting').first,
            'context': context,
            'expires_at': now.add(_ttl).toIso8601String(),
            'created_at': previous?['created_at'] ?? now.toIso8601String(),
            'updated_at': now.toIso8601String(),
          },
        ),
      ],
    );
  }

  Future<void> _clearState(
    String businessId,
    String id,
    Map<String, Object?> state,
  ) async {
    await store.applyMutations(
      actor: AuthContext(
        userId: 'whatsapp',
        businessId: businessId,
        role: 'automation',
        sessionId: id,
        actorType: 'whatsapp_webhook',
      ),
      mutations: [
        SyncMutation(
          operationId: 'conversation_clear_${uuid.v4()}',
          entity: 'whatsapp_conversations',
          entityId: id,
          operation: 'atualizar',
          localVersion: (state['_version'] as num?)?.toInt() ?? 0,
          payload: {
            ...state,
            'state': WhatsAppConversationState.idle.name,
            'context': const <String, Object?>{},
            'expires_at': DateTime.now().toUtc().add(_ttl).toIso8601String(),
          }..remove('_version'),
        ),
      ],
    );
  }

  Future<SyncChange?> _latestIncludingDeleted(
    String businessId,
    String entity,
    String id,
  ) async {
    final all = await store.pullChanges(
      businessId: businessId,
      afterCursor: 0,
      limit: 10000,
    );
    return all
        .where((item) => item.entity == entity && item.entityId == id)
        .lastOrNull;
  }

  Future<void> _reply(
    String businessId,
    String phone,
    String messageId,
    String body,
  ) async {
    await messages.enqueue(
      OutboundMessage(
        id: uuid.v4(),
        businessId: businessId,
        kind: 'whatsapp_conversation_reply',
        dedupeKey: 'reply:$messageId',
        channel: 'whatsapp',
        destination: phone,
        body: body,
        scheduledAt: DateTime.now().toUtc(),
        status: 'queued',
        attempts: 0,
      ),
    );
  }

  Future<void> _scheduleAppointmentMessages({
    required String businessId,
    required String phone,
    required String clientId,
    required String appointmentId,
    required DateTime start,
    required String serviceName,
  }) async {
    final cycle = start.toIso8601String();
    final offset = _offset(
      sources: await messages.sourceRecords(),
      businessId: businessId,
    );
    for (final item in [
      (
        'appointment_day_before',
        start.subtract(const Duration(days: 1)).copyWith(hour: 16, minute: 0),
      ),
      ('appointment_two_hours', start.subtract(const Duration(hours: 2))),
    ]) {
      await messages.enqueue(
        OutboundMessage(
          id: uuid.v4(),
          businessId: businessId,
          kind: item.$1,
          dedupeKey: 'appointment:$appointmentId:${item.$1}:$cycle',
          channel: 'whatsapp',
          destination: phone,
          body:
              'Lembrete: $serviceName em ${_displayDate(start)} às ${_displayTime(start)}.',
          scheduledAt: item.$2.subtract(Duration(minutes: offset)).toUtc(),
          status: 'queued',
          attempts: 0,
          appointmentId: appointmentId,
          clientId: clientId,
        ),
      );
    }
  }

  Future<Map<String, Object?>?> _professionalFromText(
    String businessId,
    String text,
  ) async {
    final items = await booking.publicEntities(
      businessId: businessId,
      entity: 'profissionais',
    );
    return items
        .where(
          (item) => text.contains(_normalize(item['nome']?.toString() ?? '')),
        )
        .firstOrNull;
  }

  static List<Map<String, Object?>> _matchesByName(
    List<Map<String, Object?>> items,
    String text,
  ) {
    final direct = items
        .where(
          (item) => text.contains(_normalize(item['nome']?.toString() ?? '')),
        )
        .toList();
    if (direct.isNotEmpty) {
      direct.sort(
        (a, b) => _normalize(
          b['nome']?.toString() ?? '',
        ).length.compareTo(_normalize(a['nome']?.toString() ?? '').length),
      );
      final longest = _normalize(direct.first['nome']?.toString() ?? '');
      if (text.contains(longest)) return [direct.first];
      return direct;
    }
    final words = text.split(' ').where((word) => word.length >= 3).toSet();
    return items
        .where(
          (item) => _normalize(
            item['nome']?.toString() ?? '',
          ).split(' ').any(words.contains),
        )
        .toList();
  }

  static int _offset({
    required List<AutomationSourceRecord> sources,
    required String businessId,
  }) =>
      int.tryParse(
        sources
                .where(
                  (item) =>
                      item.businessId == businessId &&
                      item.entity == 'comercios',
                )
                .firstOrNull
                ?.payload['timezone_offset_minutes']
                ?.toString() ??
            '',
      ) ??
      -180;
  static DateTime? _parseDate(String text, DateTime nowUtc, int offset) {
    final local = nowUtc.toUtc().add(Duration(minutes: offset));
    final today = DateTime(local.year, local.month, local.day);
    if (text.contains('depois de amanha')) {
      return today.add(const Duration(days: 2));
    }
    if (text.contains('amanha')) return today.add(const Duration(days: 1));
    if (text.contains('hoje')) return today;
    const days = {
      'segunda': 1,
      'terca': 2,
      'quarta': 3,
      'quinta': 4,
      'sexta': 5,
      'sabado': 6,
      'domingo': 7,
    };
    for (final entry in days.entries) {
      if (text.contains(entry.key)) {
        return today.add(
          Duration(
            days: (entry.value - today.weekday + 7) % 7 == 0
                ? 7
                : (entry.value - today.weekday + 7) % 7,
          ),
        );
      }
    }
    return null;
  }

  static Map<String, Object?>? _chooseSlot(String text, List<Map> slots) {
    final match = RegExp(
      r'\b([01]?\d|2[0-3])(?::([0-5]\d))?\s*h?\b',
    ).firstMatch(text);
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.tryParse(match.group(2) ?? '') ?? 0;
    final found = slots.where((item) {
      final date = DateTime.parse(item['start'].toString());
      return date.hour == hour && date.minute == minute;
    });
    return found.isEmpty ? null : Map<String, Object?>.from(found.first);
  }

  static DateTime? _clock(DateTime date, Object? value) {
    final parts = value?.toString().split(':');
    if (parts == null || parts.length < 2) return null;
    final h = int.tryParse(parts[0]), m = int.tryParse(parts[1]);
    return h == null || m == null
        ? null
        : DateTime(date.year, date.month, date.day, h, m);
  }

  static bool _isBookingIntent(String text) =>
      text.contains('horario') ||
      text.contains('agendar') ||
      text.contains('marcar');
  static bool _isRescheduleIntent(String text) =>
      text.contains('remarcar') ||
      text.contains('mudar meu horario') ||
      text.contains('trocar meu horario');
  static bool _isAppointmentQuery(String text) =>
      text.contains('qual meu horario') ||
      text.contains('consultar agendamento') ||
      text.contains('quando e meu horario');
  static bool _isCancelIntent(String text) =>
      text.contains('cancelar') || text.contains('nao vou conseguir');
  static bool _yes(String text) =>
      const {'sim', 'confirmo', 'ok', 'sim para cancelar'}.contains(text);
  static bool _no(String text) => const {'nao', 'não', 'manter'}.contains(text);
  static String _displayDate(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}';
  static String _displayTime(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  static String _digits(String? value) =>
      value?.replaceAll(RegExp(r'\D'), '') ?? '';
  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp('[áàâãä]'), 'a')
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[íìîï]'), 'i')
      .replaceAll(RegExp('[óòôõö]'), 'o')
      .replaceAll(RegExp('[úùûü]'), 'u')
      .replaceAll('ç', 'c')
      .trim();
}
