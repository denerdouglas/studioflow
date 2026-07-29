import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'models.dart';

abstract interface class PasswordResetNotifier {
  bool supports(String channel);
  Future<void> send({
    required String channel,
    required AccountIdentity account,
    required Uri resetUri,
  });
}

final class DisabledPasswordResetNotifier implements PasswordResetNotifier {
  const DisabledPasswordResetNotifier();
  @override
  bool supports(String channel) => false;
  @override
  Future<void> send({
    required String channel,
    required AccountIdentity account,
    required Uri resetUri,
  }) {
    throw StateError(
      'Recuperação $channel indisponível: configure um provedor no backend.',
    );
  }
}

final class HttpPasswordResetNotifier implements PasswordResetNotifier {
  final BackendConfig config;
  final http.Client client;
  HttpPasswordResetNotifier(this.config, {http.Client? client})
    : client = client ?? http.Client();

  @override
  bool supports(String channel) {
    if (channel == 'email') {
      return config.emailProviderUrl != null &&
          config.emailProviderToken != null;
    }
    if (channel == 'sms') {
      return config.smsProviderUrl != null && config.smsProviderToken != null;
    }
    return false;
  }

  @override
  Future<void> send({
    required String channel,
    required AccountIdentity account,
    required Uri resetUri,
  }) async {
    final endpoint = channel == 'email'
        ? config.emailProviderUrl
        : config.smsProviderUrl;
    final token = channel == 'email'
        ? config.emailProviderToken
        : config.smsProviderToken;
    if (endpoint == null || token == null) {
      throw StateError('Provedor de recuperação $channel não configurado.');
    }
    final destination = channel == 'email' ? account.login : account.phone;
    final providerUri = Uri.parse(endpoint);
    final resend = channel == 'email' && providerUri.host == 'api.resend.com';
    if (resend && (config.emailFrom == null || config.emailFrom!.isEmpty)) {
      throw StateError('EMAIL_FROM é obrigatório para envio pelo Resend.');
    }
    final payload = resend
        ? <String, Object?>{
            'from': config.emailFrom,
            'to': [destination],
            'subject': 'Recuperação de acesso ao StudioFlow',
            'html':
                '<p>Olá, ${_escape(account.userName)}.</p>'
                '<p>Use o link abaixo para redefinir sua senha no ${_escape(account.businessName)}. O link expira em 15 minutos.</p>'
                '<p><a href="${_escape(resetUri.toString())}">Redefinir senha</a></p>'
                '<p>Se você não solicitou, ignore esta mensagem.</p>',
          }
        : <String, Object?>{
            'destination': destination,
            'template': 'studioflow_password_reset',
            'variables': {
              'name': account.userName,
              'business': account.businessName,
              'resetUrl': resetUri.toString(),
            },
          };
    final response = await client.post(
      providerUri,
      headers: {
        'authorization': 'Bearer $token',
        'content-type': 'application/json',
        if (resend)
          'idempotency-key':
              'password-reset-${account.businessId}-${account.userId}-${DateTime.now().toUtc().hour}',
      },
      body: jsonEncode(payload),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Provedor de recuperação respondeu ${response.statusCode}.',
      );
    }
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}
