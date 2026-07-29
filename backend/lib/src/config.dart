import 'dart:io';

final class BackendConfig {
  final String databaseUrl;
  final String jwtSecret;
  final int port;
  final Uri publicBaseUrl;
  final Duration accessTokenDuration;
  final Duration refreshTokenDuration;
  final String uploadDirectory;
  final int uploadMaxBytes;
  final String? passwordResetBaseUrl;
  final String? emailProviderUrl;
  final String? emailProviderToken;
  final String? emailFrom;
  final String? smsProviderUrl;
  final String? smsProviderToken;
  final String? whatsappPhoneNumberId;
  final String? whatsappAccessToken;
  final String? whatsappVerifyToken;
  final String? metaAppSecret;
  final String? rolgAdminKey;
  final String? automationProviderUrl;
  final String? automationProviderToken;
  final String? automationWebhookToken;
  final Uri catalogBaseUrl;
  final String? catalogUserAgent;
  final String whatsappGraphApiVersion;

  const BackendConfig({
    required this.databaseUrl,
    required this.jwtSecret,
    required this.port,
    required this.publicBaseUrl,
    required this.accessTokenDuration,
    required this.refreshTokenDuration,
    required this.uploadDirectory,
    required this.uploadMaxBytes,
    this.passwordResetBaseUrl,
    this.emailProviderUrl,
    this.emailProviderToken,
    this.emailFrom,
    this.smsProviderUrl,
    this.smsProviderToken,
    this.whatsappPhoneNumberId,
    this.whatsappAccessToken,
    this.whatsappVerifyToken,
    this.metaAppSecret,
    this.rolgAdminKey,
    this.automationProviderUrl,
    this.automationProviderToken,
    this.automationWebhookToken,
    required this.catalogBaseUrl,
    this.catalogUserAgent,
    required this.whatsappGraphApiVersion,
  });

  factory BackendConfig.fromEnvironment([Map<String, String>? values]) {
    final env = values ?? Platform.environment;
    String requiredValue(String key) {
      final value = env[key]?.trim();
      if (value == null || value.isEmpty) {
        throw StateError('Variável obrigatória ausente: $key');
      }
      return value;
    }

    String? optional(String key) {
      final value = env[key]?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    final jwtSecret = requiredValue('JWT_SECRET');
    if (jwtSecret.length < 64) {
      throw StateError('JWT_SECRET deve possuir no mínimo 64 caracteres.');
    }
    return BackendConfig(
      databaseUrl: requiredValue('DATABASE_URL'),
      jwtSecret: jwtSecret,
      port: int.tryParse(env['PORT'] ?? '') ?? 8080,
      publicBaseUrl: Uri.parse(
        env['PUBLIC_BASE_URL'] ?? 'http://localhost:8080',
      ),
      accessTokenDuration: Duration(
        minutes: int.tryParse(env['ACCESS_TOKEN_MINUTES'] ?? '') ?? 15,
      ),
      refreshTokenDuration: Duration(
        days: int.tryParse(env['REFRESH_TOKEN_DAYS'] ?? '') ?? 30,
      ),
      uploadDirectory: env['UPLOAD_DIRECTORY'] ?? 'storage',
      uploadMaxBytes:
          int.tryParse(env['UPLOAD_MAX_BYTES'] ?? '') ?? 10 * 1024 * 1024,
      passwordResetBaseUrl: optional('PASSWORD_RESET_BASE_URL'),
      emailProviderUrl: optional('EMAIL_PROVIDER_URL'),
      emailProviderToken: optional('EMAIL_PROVIDER_TOKEN'),
      emailFrom: optional('EMAIL_FROM'),
      smsProviderUrl: optional('SMS_PROVIDER_URL'),
      smsProviderToken: optional('SMS_PROVIDER_TOKEN'),
      whatsappPhoneNumberId: optional('WHATSAPP_PHONE_NUMBER_ID'),
      whatsappAccessToken: optional('WHATSAPP_ACCESS_TOKEN'),
      whatsappVerifyToken: optional('WHATSAPP_VERIFY_TOKEN'),
      metaAppSecret: optional('META_APP_SECRET'),
      rolgAdminKey: optional('ROLG_ADMIN_KEY'),
      automationProviderUrl: optional('AUTOMATION_PROVIDER_URL'),
      automationProviderToken: optional('AUTOMATION_PROVIDER_TOKEN'),
      automationWebhookToken: optional('AUTOMATION_WEBHOOK_TOKEN'),
      catalogBaseUrl: Uri.parse(
        env['CATALOG_BASE_URL'] ?? 'https://world.openfoodfacts.org',
      ),
      catalogUserAgent: optional('CATALOG_USER_AGENT'),
      whatsappGraphApiVersion: env['WHATSAPP_GRAPH_API_VERSION'] ?? 'v23.0',
    );
  }
}
