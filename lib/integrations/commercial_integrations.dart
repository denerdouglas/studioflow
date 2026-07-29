import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/utils/id_generator.dart';
import '../database/database_service.dart';

enum AppEnvironment { development, staging, production }

abstract final class EnvironmentConfig {
  static const environment = String.fromEnvironment(
    'STUDIOFLOW_ENV',
    defaultValue: 'development',
  );

  static AppEnvironment get current => AppEnvironment.values.firstWhere(
    (value) => value.name == environment,
    orElse: () => AppEnvironment.development,
  );

  /// Apenas endpoint público. Segredos pertencem exclusivamente ao backend.
  static const publicBackendUrl = String.fromEnvironment(
    'STUDIOFLOW_PUBLIC_BACKEND_URL',
    defaultValue: '',
  );
}

class OutboundMessage {
  final String commerceId;
  final String recipient;
  final String content;
  final String? template;

  const OutboundMessage({
    required this.commerceId,
    required this.recipient,
    required this.content,
    this.template,
  });
}

abstract interface class WhatsAppProvider {
  String get id;
  bool get isConfigured;
  Future<String> send(OutboundMessage message);
}

class SimulatedWhatsAppProvider implements WhatsAppProvider {
  final Future<Database> Function() _database;
  SimulatedWhatsAppProvider({Future<Database> Function()? databaseProvider})
    : _database = databaseProvider ?? (() => DatabaseService.instance.database);

  @override
  String get id => 'simulated';

  @override
  bool get isConfigured => true;

  @override
  Future<String> send(OutboundMessage message) async {
    final db = await _database();
    final id = 'wa_${IdGenerator.temporal()}';
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('whatsapp_fila', {
      'id': id,
      'comercio_id': message.commerceId,
      'destinatario': message.recipient,
      'template': message.template,
      'payload_json': jsonEncode({'content': message.content}),
      'status': 'simulado',
      'criado_em': now,
      'atualizado_em': now,
    });
    return id;
  }
}

class OfficialWhatsAppProvider implements WhatsAppProvider {
  @override
  String get id => 'official_backend';

  @override
  bool get isConfigured => EnvironmentConfig.publicBackendUrl.isNotEmpty;

  @override
  Future<String> send(OutboundMessage message) {
    throw StateError(
      'WhatsApp oficial indisponível. Configure um backend seguro; nenhuma credencial fica no aplicativo.',
    );
  }
}

abstract interface class AiAssistantProvider {
  String get id;
  Future<String> answer({required String commerceId, required String question});
}

class SafeFallbackAiProvider implements AiAssistantProvider {
  @override
  String get id => 'safe_fallback';

  @override
  Future<String> answer({
    required String commerceId,
    required String question,
  }) async =>
      'Não tenho informação suficiente para responder com segurança. Vou encaminhar para atendimento humano.';
}

abstract interface class ConversationRepository {
  Future<String> start({required String commerceId, String? customerId});
}

abstract interface class MessageRepository {
  Future<void> save({
    required String commerceId,
    required String conversationId,
    required String sender,
    required String content,
  });
}

abstract interface class AutomationRepository {
  Future<bool> isEnabled(String commerceId, String automation);
}

abstract interface class SubscriptionPaymentProvider {
  String get id;
  bool get supportsPix;
  bool get supportsCards;
}
