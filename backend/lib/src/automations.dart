import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';
import 'package:studioflow_backend/src/database_config.dart';
import 'package:uuid/uuid.dart';

final class AutomationSourceRecord {
  final String businessId;
  final String entity;
  final String entityId;
  final Map<String, Object?> payload;

  const AutomationSourceRecord({
    required this.businessId,
    required this.entity,
    required this.entityId,
    required this.payload,
  });
}

final class OutboundMessage {
  final String id;
  final String businessId;
  final String kind;
  final String dedupeKey;
  final String channel;
  final String destination;
  final String body;
  final DateTime scheduledAt;
  final String status;
  final int attempts;
  final DateTime? nextAttemptAt;
  final String? externalId;
  final String? lastError;
  final String? appointmentId;
  final String? clientId;
  final Map<String, Object?> metadata;

  const OutboundMessage({
    required this.id,
    required this.businessId,
    required this.kind,
    required this.dedupeKey,
    required this.channel,
    required this.destination,
    required this.body,
    required this.scheduledAt,
    required this.status,
    required this.attempts,
    this.nextAttemptAt,
    this.externalId,
    this.lastError,
    this.appointmentId,
    this.clientId,
    this.metadata = const {},
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'businessId': businessId,
    'kind': kind,
    'channel': channel,
    'destinationMasked': _mask(destination),
    'body': body,
    'scheduledAt': scheduledAt.toUtc().toIso8601String(),
    'status': status,
    'attempts': attempts,
    'nextAttemptAt': nextAttemptAt?.toUtc().toIso8601String(),
    'externalId': externalId,
    'lastError': lastError,
    'appointmentId': appointmentId,
    'clientId': clientId,
    'metadata': metadata,
  };

  static String _mask(String value) {
    if (value.length <= 4) return '****';
    return '${'*' * (value.length - 4)}${value.substring(value.length - 4)}';
  }
}

abstract interface class MessageAutomationStore {
  Future<List<AutomationSourceRecord>> sourceRecords();
  Future<bool> enqueue(OutboundMessage message);
  Future<List<OutboundMessage>> claimDue(DateTime now, {int limit = 50});
  Future<void> markSent(
    String id, {
    required String externalId,
    required DateTime sentAt,
  });
  Future<void> markFailed(
    String id, {
    required String error,
    required DateTime retryAt,
    required bool terminal,
  });
  Future<void> updateDelivery({
    required String externalId,
    required String status,
    String? error,
  });
  Future<int> cancelAppointment({
    required String businessId,
    required String appointmentId,
    required String reason,
  });
  Future<List<OutboundMessage>> history(String businessId, {int limit = 100});
  Future<void> close();
}

final class MemoryMessageAutomationStore implements MessageAutomationStore {
  final List<AutomationSourceRecord> sources = [];
  final Map<String, OutboundMessage> _messages = {};
  final Set<String> _dedupe = {};

  @override
  Future<List<AutomationSourceRecord>> sourceRecords() async =>
      List.unmodifiable(sources);

  @override
  Future<bool> enqueue(OutboundMessage message) async {
    final key = '${message.businessId}::${message.dedupeKey}';
    if (!_dedupe.add(key)) return false;
    _messages[message.id] = message;
    return true;
  }

  @override
  Future<List<OutboundMessage>> claimDue(DateTime now, {int limit = 50}) async {
    final due = _messages.values
        .where(
          (m) =>
              const {'queued', 'retry'}.contains(m.status) &&
              !m.scheduledAt.isAfter(now) &&
              (m.nextAttemptAt == null || !m.nextAttemptAt!.isAfter(now)),
        )
        .take(limit)
        .toList();
    for (final message in due) {
      _messages[message.id] = _copy(
        message,
        status: 'sending',
        attempts: message.attempts + 1,
      );
    }
    return due
        .map((m) => _copy(m, status: 'sending', attempts: m.attempts + 1))
        .toList();
  }

  @override
  Future<void> markSent(
    String id, {
    required String externalId,
    required DateTime sentAt,
  }) async {
    final message = _messages[id];
    if (message == null) return;
    _messages[id] = _copy(
      message,
      status: 'sent',
      externalId: externalId,
      nextAttemptAt: sentAt,
    );
  }

  @override
  Future<void> markFailed(
    String id, {
    required String error,
    required DateTime retryAt,
    required bool terminal,
  }) async {
    final message = _messages[id];
    if (message == null) return;
    _messages[id] = _copy(
      message,
      status: terminal ? 'error' : 'retry',
      nextAttemptAt: retryAt,
      lastError: error,
    );
  }

  @override
  Future<void> updateDelivery({
    required String externalId,
    required String status,
    String? error,
  }) async {
    final entry = _messages.entries
        .where((e) => e.value.externalId == externalId)
        .firstOrNull;
    if (entry == null) return;
    _messages[entry.key] = _copy(entry.value, status: status, lastError: error);
  }

  @override
  Future<int> cancelAppointment({
    required String businessId,
    required String appointmentId,
    required String reason,
  }) async {
    var count = 0;
    for (final entry in _messages.entries.toList()) {
      final message = entry.value;
      if (message.businessId == businessId &&
          message.appointmentId == appointmentId &&
          const {'queued', 'retry', 'sending'}.contains(message.status)) {
        _messages[entry.key] = _copy(
          message,
          status: 'cancelled',
          lastError: reason,
        );
        count++;
      }
    }
    return count;
  }

  @override
  Future<List<OutboundMessage>> history(
    String businessId, {
    int limit = 100,
  }) async {
    final result =
        _messages.values.where((m) => m.businessId == businessId).toList()
          ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
    return result.take(limit).toList();
  }

  @override
  Future<void> close() async {}

  static OutboundMessage _copy(
    OutboundMessage value, {
    String? status,
    int? attempts,
    DateTime? nextAttemptAt,
    String? externalId,
    String? lastError,
  }) => OutboundMessage(
    id: value.id,
    businessId: value.businessId,
    kind: value.kind,
    dedupeKey: value.dedupeKey,
    channel: value.channel,
    destination: value.destination,
    body: value.body,
    scheduledAt: value.scheduledAt,
    status: status ?? value.status,
    attempts: attempts ?? value.attempts,
    nextAttemptAt: nextAttemptAt ?? value.nextAttemptAt,
    externalId: externalId ?? value.externalId,
    lastError: lastError,
    appointmentId: value.appointmentId,
    clientId: value.clientId,
    metadata: value.metadata,
  );
}

final class PostgresMessageAutomationStore implements MessageAutomationStore {
  final Pool _pool;

  PostgresMessageAutomationStore._(this._pool);

  factory PostgresMessageAutomationStore.fromUrl(String url) {
    return PostgresMessageAutomationStore._(DatabaseConfig.createPool(url));
  }

  @override
  Future<List<AutomationSourceRecord>> sourceRecords() async {
    return _pool.runTx((tx) async {
      await _enableWorker(tx);
      final result = await tx.execute('''
        SELECT business_id, entity, entity_id, payload
        FROM sync_records
        WHERE deleted=FALSE AND entity IN (
          'comercios','clientes','profissionais','servicos','agendamentos',
          'modelos_mensagens'
        )
      ''');
      return result.map((entry) {
        final row = entry.toColumnMap();
        return AutomationSourceRecord(
          businessId: row['business_id'] as String,
          entity: row['entity'] as String,
          entityId: row['entity_id'] as String,
          payload: _jsonMap(row['payload']),
        );
      }).toList();
    });
  }

  @override
  Future<bool> enqueue(OutboundMessage message) async {
    return _pool.runTx((tx) async {
      await _enableWorker(tx);
      final result = await tx.execute(
        Sql.named('''
          INSERT INTO outbound_messages (
            id,business_id,kind,dedupe_key,channel,destination,body,
            scheduled_at,status,attempts,appointment_id,client_id,metadata
          ) VALUES (
            @id,@businessId,@kind,@dedupeKey,@channel,@destination,@body,
            @scheduledAt,'queued',0,@appointmentId,@clientId,
            CAST(@metadata AS jsonb)
          )
          ON CONFLICT (business_id,dedupe_key) DO NOTHING
        '''),
        parameters: {
          'id': message.id,
          'businessId': message.businessId,
          'kind': message.kind,
          'dedupeKey': message.dedupeKey,
          'channel': message.channel,
          'destination': message.destination,
          'body': message.body,
          'scheduledAt': message.scheduledAt,
          'appointmentId': message.appointmentId,
          'clientId': message.clientId,
          'metadata': jsonEncode(message.metadata),
        },
      );
      return result.affectedRows > 0;
    });
  }

  @override
  Future<List<OutboundMessage>> claimDue(DateTime now, {int limit = 50}) {
    return _pool.runTx((tx) async {
      await _enableWorker(tx);
      final result = await tx.execute(
        Sql.named('''
          SELECT * FROM outbound_messages
          WHERE status IN ('queued','retry')
            AND scheduled_at<=@now
            AND (next_attempt_at IS NULL OR next_attempt_at<=@now)
          ORDER BY scheduled_at
          FOR UPDATE SKIP LOCKED LIMIT @limit
        '''),
        parameters: {'now': now, 'limit': limit.clamp(1, 200)},
      );
      final messages = result
          .map((row) => _message(row.toColumnMap()))
          .toList();
      for (final message in messages) {
        await tx.execute(
          Sql.named('''
            UPDATE outbound_messages SET status='sending',
              attempts=attempts+1, updated_at=now() WHERE id=@id
          '''),
          parameters: {'id': message.id},
        );
      }
      return messages
          .map(
            (m) => OutboundMessage(
              id: m.id,
              businessId: m.businessId,
              kind: m.kind,
              dedupeKey: m.dedupeKey,
              channel: m.channel,
              destination: m.destination,
              body: m.body,
              scheduledAt: m.scheduledAt,
              status: 'sending',
              attempts: m.attempts + 1,
              nextAttemptAt: m.nextAttemptAt,
              externalId: m.externalId,
              lastError: m.lastError,
              appointmentId: m.appointmentId,
              clientId: m.clientId,
              metadata: m.metadata,
            ),
          )
          .toList();
    });
  }

  Future<void> _updateSyncRecord(
    TxSession tx,
    String outboundMessageId,
    String newStatus, {
    String? newExternalId,
  }) async {
    final params = {'id': outboundMessageId, 'status': newStatus};
    var query = '''
        UPDATE sync_records sr
        SET payload = jsonb_set(
          payload,
          '{status}',
          to_jsonb(@status::text)
        ),
        server_version = server_version + 1,
        updated_at = now()
        FROM outbound_messages om
        WHERE om.id = @id
        AND sr.entity = 'whatsapp_fila'
        AND sr.entity_id = om.metadata->>'whatsapp_fila_id'
        AND sr.business_id = om.business_id
    ''';
    if (newExternalId != null) {
      params['externalId'] = newExternalId;
      query = '''
        UPDATE sync_records sr
        SET payload = jsonb_set(
          jsonb_set(
            payload,
            '{status}',
            to_jsonb(@status::text)
          ),
          '{provider_message_id}',
          to_jsonb(@externalId::text)
        ),
        server_version = server_version + 1,
        updated_at = now()
        FROM outbound_messages om
        WHERE om.id = @id
        AND sr.entity = 'whatsapp_fila'
        AND sr.entity_id = om.metadata->>'whatsapp_fila_id'
        AND sr.business_id = om.business_id
      ''';
    }

    await tx.execute(Sql.named(query), parameters: params);
  }

  @override
  Future<void> markSent(
    String id, {
    required String externalId,
    required DateTime sentAt,
  }) async {
    await _pool.runTx((tx) async {
      await _enableWorker(tx);
      await tx.execute(
        Sql.named('''
          UPDATE outbound_messages SET status='sent', external_id=@externalId,
            sent_at=@sentAt, last_error=NULL, updated_at=now() WHERE id=@id
        '''),
        parameters: {'id': id, 'externalId': externalId, 'sentAt': sentAt},
      );
      await _attempt(tx, id, 'sent', null);
      await _updateSyncRecord(tx, id, 'enviada', newExternalId: externalId);
    });
  }

  @override
  Future<void> markFailed(
    String id, {
    required String error,
    required DateTime retryAt,
    required bool terminal,
  }) async {
    await _pool.runTx((tx) async {
      await _enableWorker(tx);
      await tx.execute(
        Sql.named('''
          UPDATE outbound_messages SET status=@status, last_error=@error,
            next_attempt_at=@retryAt, updated_at=now() WHERE id=@id
        '''),
        parameters: {
          'id': id,
          'status': terminal ? 'error' : 'retry',
          'error': error,
          'retryAt': retryAt,
        },
      );
      await _attempt(tx, id, terminal ? 'error' : 'retry', error);
      await _updateSyncRecord(tx, id, terminal ? 'falhou' : 'na_fila');
    });
  }

  Future<void> _attempt(
    Session executor,
    String id,
    String status,
    String? error,
  ) async {
    await executor.execute(
      Sql.named('''
        INSERT INTO message_delivery_attempts
          (message_id,attempt_number,status,error)
        SELECT id,attempts,@status,@error FROM outbound_messages WHERE id=@id
      '''),
      parameters: {'id': id, 'status': status, 'error': error},
    );
  }

  @override
  Future<void> updateDelivery({
    required String externalId,
    required String status,
    String? error,
  }) async {
    if (!const {'sent', 'delivered', 'read', 'error'}.contains(status)) {
      throw ArgumentError('Status de entrega inválido.');
    }
    await _pool.runTx((tx) async {
      await _enableWorker(tx);
      final updated = await tx.execute(
        Sql.named('''
          UPDATE outbound_messages SET status=@status, last_error=@error,
            delivered_at=CASE WHEN @status IN ('delivered','read')
              THEN now() ELSE delivered_at END, updated_at=now()
          WHERE external_id=@externalId
          RETURNING id
        '''),
        parameters: {
          'externalId': externalId,
          'status': status,
          'error': error,
        },
      );
      if (updated.isNotEmpty) {
        final id = updated.single.toColumnMap()['id'] as String;
        final mappedStatus = status == 'error'
            ? 'falhou'
            : status == 'delivered'
            ? 'entregue'
            : status == 'read'
            ? 'lida'
            : 'enviada';
        await _updateSyncRecord(tx, id, mappedStatus);
      }
    });
  }

  @override
  Future<int> cancelAppointment({
    required String businessId,
    required String appointmentId,
    required String reason,
  }) async {
    return _pool.runTx((tx) async {
      await _enableWorker(tx);
      final result = await tx.execute(
        Sql.named('''
          UPDATE outbound_messages
          SET status='cancelled', last_error=@reason, updated_at=now()
          WHERE business_id=@businessId AND appointment_id=@appointmentId
            AND status IN ('queued','retry','sending')
        '''),
        parameters: {
          'businessId': businessId,
          'appointmentId': appointmentId,
          'reason': reason,
        },
      );
      return result.affectedRows;
    });
  }

  @override
  Future<List<OutboundMessage>> history(
    String businessId, {
    int limit = 100,
  }) async {
    return _pool.runTx((tx) async {
      await tx.execute(
        Sql.named("SELECT set_config('app.business_id', @businessId, true)"),
        parameters: {'businessId': businessId},
      );
      final result = await tx.execute(
        Sql.named('''
          SELECT * FROM outbound_messages WHERE business_id=@businessId
          ORDER BY scheduled_at DESC LIMIT @limit
        '''),
        parameters: {'businessId': businessId, 'limit': limit.clamp(1, 500)},
      );
      return result.map((row) => _message(row.toColumnMap())).toList();
    });
  }

  static Future<void> _enableWorker(Session session) async {
    await session.execute(
      "SELECT set_config('app.automation_worker', '1', true)",
    );
  }

  static OutboundMessage _message(Map<String, dynamic> row) => OutboundMessage(
    id: row['id'] as String,
    businessId: row['business_id'] as String,
    kind: row['kind'] as String,
    dedupeKey: row['dedupe_key'] as String,
    channel: row['channel'] as String,
    destination: row['destination'] as String,
    body: row['body'] as String,
    scheduledAt: row['scheduled_at'] as DateTime,
    status: row['status'] as String,
    attempts: row['attempts'] as int,
    nextAttemptAt: row['next_attempt_at'] as DateTime?,
    externalId: row['external_id'] as String?,
    lastError: row['last_error'] as String?,
    appointmentId: row['appointment_id'] as String?,
    clientId: row['client_id'] as String?,
    metadata: _jsonMap(row['metadata']),
  );

  static Map<String, Object?> _jsonMap(Object? value) {
    if (value is Map) return Map<String, Object?>.from(value);
    if (value is String) {
      return Map<String, Object?>.from(jsonDecode(value) as Map);
    }
    return const {};
  }

  @override
  Future<void> close() => _pool.close();
}

abstract interface class AutomationMessageSender {
  bool get configured;
  Future<String> send(OutboundMessage message);
}

final class DisabledAutomationMessageSender implements AutomationMessageSender {
  const DisabledAutomationMessageSender();

  @override
  bool get configured => false;

  @override
  Future<String> send(OutboundMessage message) {
    throw StateError(
      'Provedor automático não configurado no backend. '
      'O registro permanece no histórico para nova tentativa.',
    );
  }
}

final class WhatsAppCloudApiSender implements AutomationMessageSender {
  final String phoneNumberId;
  final String accessToken;
  final String graphApiVersion;
  final Map<String, String> templates;
  final http.Client client;

  WhatsAppCloudApiSender({
    required this.phoneNumberId,
    required this.accessToken,
    required this.graphApiVersion,
    required this.templates,
    http.Client? client,
  }) : client = client ?? http.Client();

  @override
  bool get configured =>
      phoneNumberId.isNotEmpty &&
      accessToken.isNotEmpty &&
      templates.isNotEmpty &&
      templates.values.every((value) => value.isNotEmpty);

  @override
  Future<String> send(OutboundMessage message) async {
    final template = templates[message.kind];
    if (template == null || template.isEmpty) {
      throw StateError('Template Meta não configurado para ${message.kind}.');
    }
    final endpoint = Uri.https(
      'graph.facebook.com',
      '/$graphApiVersion/$phoneNumberId/messages',
    );
    final response = await client
        .post(
          endpoint,
          headers: {
            'authorization': 'Bearer $accessToken',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'messaging_product': 'whatsapp',
            'to': message.destination.replaceAll(RegExp(r'[^0-9]'), ''),
            'type': 'template',
            'template': {
              'name': template,
              'language': {'code': 'pt_BR'},
              'components': [
                {
                  'type': 'body',
                  'parameters': [
                    {'type': 'text', 'text': message.body},
                  ],
                },
              ],
            },
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Meta respondeu HTTP ${response.statusCode}: '
        '${response.body.substring(0, min(300, response.body.length))}',
      );
    }
    final body = Map<String, Object?>.from(jsonDecode(response.body) as Map);
    final messages = body['messages'];
    if (messages is! List || messages.isEmpty || messages.first is! Map) {
      throw StateError('Meta não retornou o identificador da mensagem.');
    }
    return (messages.first as Map)['id']?.toString() ?? message.id;
  }
}

final class HttpAutomationMessageSender implements AutomationMessageSender {
  final Uri endpoint;
  final String token;
  final http.Client client;

  HttpAutomationMessageSender({
    required this.endpoint,
    required this.token,
    http.Client? client,
  }) : client = client ?? http.Client();

  @override
  bool get configured => token.isNotEmpty;

  @override
  Future<String> send(OutboundMessage message) async {
    final response = await client.post(
      endpoint,
      headers: {
        'authorization': 'Bearer $token',
        'content-type': 'application/json',
        'idempotency-key': message.dedupeKey,
      },
      body: jsonEncode({
        'businessId': message.businessId,
        'channel': message.channel,
        'destination': message.destination,
        'message': message.body,
        'metadata': message.metadata,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Provedor respondeu HTTP ${response.statusCode}: '
        '${response.body.substring(0, min(300, response.body.length))}',
      );
    }
    final body = response.body.isEmpty
        ? const <String, Object?>{}
        : Map<String, Object?>.from(jsonDecode(response.body) as Map);
    return body['externalId']?.toString() ?? message.id;
  }
}

final class MessageAutomationEngine {
  final MessageAutomationStore store;
  final AutomationMessageSender sender;
  final Uri publicBaseUrl;
  final Uuid uuid;
  Timer? _timer;
  bool _running = false;

  MessageAutomationEngine({
    required this.store,
    required this.sender,
    required this.publicBaseUrl,
    Uuid? uuid,
  }) : uuid = uuid ?? const Uuid();

  void start({Duration interval = const Duration(minutes: 1)}) {
    _timer?.cancel();
    unawaited(runOnce());
    _timer = Timer.periodic(interval, (_) => unawaited(runOnce()));
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  Future<Map<String, int>> runOnce([DateTime? clock]) async {
    if (_running) return const {'scheduled': 0, 'sent': 0, 'failed': 0};
    _running = true;
    try {
      final now = (clock ?? DateTime.now()).toUtc();
      final scheduled = await schedule(now);
      final result = await dispatch(now);
      return {'scheduled': scheduled, 'sent': result.$1, 'failed': result.$2};
    } finally {
      _running = false;
    }
  }

  Future<int> schedule(DateTime nowUtc) async {
    final records = await store.sourceRecords();
    final grouped = <String, List<AutomationSourceRecord>>{};
    for (final record in records) {
      grouped.putIfAbsent(record.businessId, () => []).add(record);
    }
    var created = 0;
    for (final entry in grouped.entries) {
      created += await _scheduleBusiness(entry.key, entry.value, nowUtc);
    }
    return created;
  }

  Future<int> _scheduleBusiness(
    String businessId,
    List<AutomationSourceRecord> records,
    DateTime nowUtc,
  ) async {
    final byEntity = <String, Map<String, Map<String, Object?>>>{};
    for (final record in records) {
      byEntity.putIfAbsent(record.entity, () => {})[record.entityId] =
          record.payload;
    }
    final business =
        byEntity['comercios']?.values.firstOrNull ??
        <String, Object?>{'nome': 'StudioFlow'};
    final clients = byEntity['clientes'] ?? const {};
    final professionals = byEntity['profissionais'] ?? const {};
    final services = byEntity['servicos'] ?? const {};
    final appointments = byEntity['agendamentos'] ?? const {};
    final templates = <String, String>{};
    for (final model in (byEntity['modelos_mensagens'] ?? const {}).values) {
      if (model['ativo'] != 0) {
        templates[model['chave']?.toString() ?? ''] =
            model['texto']?.toString() ?? '';
      }
    }
    var created = 0;
    final localNow = nowUtc.subtract(const Duration(hours: 3));
    for (final entry in appointments.entries) {
      final appointment = entry.value;
      final status = appointment['status']?.toString() ?? '';
      if (status == 'cancelado' || appointment['excluido'] == 1) {
        await store.cancelAppointment(
          businessId: businessId,
          appointmentId: entry.key,
          reason:
              appointment['cancelamento_motivo']?.toString() ??
              appointment['exclusao_motivo']?.toString() ??
              'Agendamento cancelado no StudioFlow.',
        );
        continue;
      }
      if (const {'concluido', 'faltou'}.contains(status)) continue;
      final parsedStart = DateTime.tryParse(
        appointment['inicio']?.toString() ?? '',
      );
      final localStart = parsedStart == null
          ? null
          : DateTime.utc(
              parsedStart.year,
              parsedStart.month,
              parsedStart.day,
              parsedStart.hour,
              parsedStart.minute,
              parsedStart.second,
            );
      if (localStart == null || localStart.isBefore(localNow)) continue;
      final client = clients[appointment['cliente_id']] ?? const {};
      if (client['consentimento_whatsapp'] != 1 &&
          client['consentimento_whatsapp'] != true) {
        continue;
      }
      final professional =
          professionals[appointment['profissional_id']] ?? const {};
      final service = services[appointment['servico_id']] ?? const {};
      final destination =
          client['whatsapp']?.toString() ??
          client['telefone']?.toString() ??
          '';
      if (destination.isEmpty) continue;
      final variables = _appointmentVariables(
        business,
        client,
        professional,
        service,
        localStart,
        entry.key,
      );
      final previousDayLocal = DateTime.utc(
        localStart.year,
        localStart.month,
        localStart.day - 1,
        16,
      );
      created += await _enqueue(
        businessId: businessId,
        kind: 'appointment_day_before',
        dedupeKey: 'appointment:${entry.key}:day_before',
        destination: destination,
        body: _render(
          templates['lembrete_dia_anterior'] ?? _defaultDayBeforeTemplate,
          variables,
        ),
        scheduledAt: previousDayLocal.add(const Duration(hours: 3)),
        appointmentId: entry.key,
        clientId: appointment['cliente_id']?.toString(),
        metadata: variables,
      );
      created += await _enqueue(
        businessId: businessId,
        kind: 'appointment_two_hours',
        dedupeKey: 'appointment:${entry.key}:two_hours',
        destination: destination,
        body: _render(
          templates['lembrete_duas_horas'] ?? _defaultTwoHoursTemplate,
          variables,
        ),
        scheduledAt: localStart
            .add(const Duration(hours: 3))
            .subtract(const Duration(hours: 2)),
        appointmentId: entry.key,
        clientId: appointment['cliente_id']?.toString(),
        metadata: variables,
      );
    }

    for (final entry in clients.entries) {
      final client = entry.value;
      if (client['ativo'] == 0) continue;
      if (client['consentimento_whatsapp'] != 1 &&
          client['consentimento_whatsapp'] != true) {
        continue;
      }
      final birthday = DateTime.tryParse(
        client['data_nascimento']?.toString() ?? '',
      );
      if (birthday == null ||
          birthday.month != localNow.month ||
          birthday.day != localNow.day) {
        continue;
      }
      final destination =
          client['whatsapp']?.toString() ??
          client['telefone']?.toString() ??
          '';
      final variables = _birthdayVariables(
        business,
        client,
        birthday,
        localNow,
        appointments.values,
        services,
      );
      final dateKey =
          '${localNow.year}-${localNow.month.toString().padLeft(2, '0')}-'
          '${localNow.day.toString().padLeft(2, '0')}';
      final ownerDestination = business['telefone']?.toString() ?? '';
      if (ownerDestination.isNotEmpty) {
        created += await _enqueue(
          businessId: businessId,
          kind: 'birthday_owner',
          dedupeKey: 'birthday_owner:${entry.key}:$dateKey',
          destination: ownerDestination,
          body: _render(
            templates['alerta_aniversario_dona'] ??
                _defaultBirthdayOwnerTemplate,
            variables,
          ),
          scheduledAt: DateTime.utc(
            localNow.year,
            localNow.month,
            localNow.day,
            8,
          ).add(const Duration(hours: 3)),
          clientId: entry.key,
          metadata: variables,
        );
      }
      if (destination.isNotEmpty) {
        created += await _enqueue(
          businessId: businessId,
          kind: 'birthday_client',
          dedupeKey: 'birthday_client:${entry.key}:${localNow.year}',
          destination: destination,
          body: _render(
            templates['aniversario_cliente'] ?? _defaultBirthdayClientTemplate,
            variables,
          ),
          scheduledAt: DateTime.utc(
            localNow.year,
            localNow.month,
            localNow.day,
            9,
          ).add(const Duration(hours: 3)),
          clientId: entry.key,
          metadata: variables,
        );
      }
    }
    return created;
  }

  Future<int> _enqueue({
    required String businessId,
    required String kind,
    required String dedupeKey,
    required String destination,
    required String body,
    required DateTime scheduledAt,
    String? appointmentId,
    String? clientId,
    required Map<String, Object?> metadata,
  }) async {
    final inserted = await store.enqueue(
      OutboundMessage(
        id: uuid.v4(),
        businessId: businessId,
        kind: kind,
        dedupeKey: dedupeKey,
        channel: 'whatsapp',
        destination: destination,
        body: body,
        scheduledAt: scheduledAt.toUtc(),
        status: 'queued',
        attempts: 0,
        appointmentId: appointmentId,
        clientId: clientId,
        metadata: metadata,
      ),
    );
    return inserted ? 1 : 0;
  }

  Future<(int, int)> dispatch(DateTime now) async {
    final messages = await store.claimDue(now);
    var sent = 0;
    var failed = 0;
    for (final message in messages) {
      try {
        final externalId = await sender.send(message);
        await store.markSent(message.id, externalId: externalId, sentAt: now);
        sent++;
      } catch (error) {
        failed++;
        final terminal = message.attempts >= 5;
        final minutes = min(60, pow(2, message.attempts).toInt());
        await store.markFailed(
          message.id,
          error: error.toString(),
          retryAt: now.add(Duration(minutes: minutes)),
          terminal: terminal,
        );
      }
    }
    return (sent, failed);
  }

  Map<String, Object?> _appointmentVariables(
    Map<String, Object?> business,
    Map<String, Object?> client,
    Map<String, Object?> professional,
    Map<String, Object?> service,
    DateTime start,
    String appointmentId,
  ) {
    final actionBase = publicBaseUrl.resolve('/a/$appointmentId');
    return {
      'cliente': client['nome'] ?? '',
      'salao': business['nome_exibicao'] ?? business['nome'] ?? '',
      'profissional': professional['nome'] ?? '',
      'servico': service['nome'] ?? '',
      'data':
          '${start.day.toString().padLeft(2, '0')}/'
          '${start.month.toString().padLeft(2, '0')}/${start.year}',
      'hora':
          '${start.hour.toString().padLeft(2, '0')}:'
          '${start.minute.toString().padLeft(2, '0')}',
      'localizacao': business['endereco'] ?? '',
      'confirmacao': actionBase.replace(queryParameters: {'acao': 'confirmar'}),
      'reagendamento': actionBase.replace(
        queryParameters: {'acao': 'reagendar'},
      ),
      'cancelamento': actionBase.replace(queryParameters: {'acao': 'cancelar'}),
    };
  }

  Map<String, Object?> _birthdayVariables(
    Map<String, Object?> business,
    Map<String, Object?> client,
    DateTime birthday,
    DateTime localNow,
    Iterable<Map<String, Object?>> appointments,
    Map<String, Map<String, Object?>> services,
  ) {
    final clientId = client['id']?.toString();
    final history =
        appointments
            .where((a) => a['cliente_id']?.toString() == clientId)
            .toList()
          ..sort(
            (a, b) => (b['inicio']?.toString() ?? '').compareTo(
              a['inicio']?.toString() ?? '',
            ),
          );
    final serviceCount = <String, int>{};
    for (final appointment in history) {
      final id = appointment['servico_id']?.toString();
      if (id != null) serviceCount[id] = (serviceCount[id] ?? 0) + 1;
    }
    final favoriteId = serviceCount.entries.isEmpty
        ? null
        : (serviceCount.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value)))
              .first
              .key;
    final registered = DateTime.tryParse(
      client['data_cadastro']?.toString() ?? '',
    );
    return {
      'cliente': client['nome'] ?? '',
      'salao': business['nome_exibicao'] ?? business['nome'] ?? '',
      'idade': localNow.year - birthday.year,
      'tempo_cliente_dias': registered == null
          ? 0
          : localNow.difference(registered).inDays,
      'ultimo_atendimento': history.firstOrNull?['inicio'] ?? 'Nenhum',
      'valor_gasto': client['total_gasto'] ?? 0,
      'servico_favorito': favoriteId == null
          ? 'Ainda não identificado'
          : services[favoriteId]?['nome'] ?? '',
      'cupom': 'ANIVERSARIO${localNow.year}',
      'desconto': '10%',
      'presente': 'um presente especial',
      'imagem': '',
      'link_agendamento': publicBaseUrl.resolve('/agendar').toString(),
    };
  }

  static String _render(String template, Map<String, Object?> variables) {
    var result = template;
    for (final entry in variables.entries) {
      result = result
          .replaceAll('[${entry.key}]', entry.value.toString())
          .replaceAll('{{${entry.key}}}', entry.value.toString());
    }
    return result;
  }

  static const _defaultDayBeforeTemplate =
      'Olá, [cliente]! Lembrete do seu atendimento amanhã no [salao], '
      'às [hora], com [profissional]. Serviço: [servico]. '
      'Local: [localizacao]\nConfirmar: [confirmacao]\n'
      'Reagendar: [reagendamento]\nCancelar: [cancelamento]';
  static const _defaultTwoHoursTemplate =
      'Olá, [cliente]! Seu atendimento no [salao] começa em duas horas, '
      'às [hora], com [profissional]. Serviço: [servico]. Local: [localizacao]. '
      'Confirmar: [confirmacao] Reagendar: [reagendamento] '
      'Cancelar: [cancelamento]';
  static const _defaultBirthdayOwnerTemplate =
      '🎂 Hoje é aniversário de [cliente]. Idade: [idade]. '
      'Cliente há [tempo_cliente_dias] dias, último atendimento: '
      '[ultimo_atendimento], total gasto: R\$ [valor_gasto], '
      'serviço favorito: [servico_favorito].';
  static const _defaultBirthdayClientTemplate =
      'Parabéns, [cliente]! A equipe [salao] deseja um aniversário '
      'maravilhoso. Seu cupom é [cupom]. Agende: [link_agendamento]';
}
