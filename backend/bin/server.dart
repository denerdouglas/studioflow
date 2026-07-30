import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:studioflow_backend/studioflow_backend.dart';

Future<void> main() async {
  final config = BackendConfig.fromEnvironment();
  final store = PostgresBackendStore.fromUrl(config.databaseUrl);
  final marketplace = MarketplacePostgresStore.fromUrl(config.databaseUrl);
  final automations = PostgresMessageAutomationStore.fromUrl(
    config.databaseUrl,
  );
  final catalogStore = PostgresCatalogStore.fromUrl(config.databaseUrl);
  final catalog = CatalogLookupService(
    store: catalogStore,
    baseUrl: config.catalogBaseUrl,
    userAgent: config.catalogUserAgent,
  );
  final AutomationMessageSender sender;
  if (config.whatsappPhoneNumberId != null &&
      config.whatsappAccessToken != null) {
    sender = WhatsAppCloudApiSender(
      phoneNumberId: config.whatsappPhoneNumberId!,
      accessToken: config.whatsappAccessToken!,
      graphApiVersion: config.whatsappGraphApiVersion,
      templates: {
        'appointment_day_before':
            Platform.environment['WHATSAPP_TEMPLATE_DAY_BEFORE'] ?? '',
        'appointment_two_hours':
            Platform.environment['WHATSAPP_TEMPLATE_TWO_HOURS'] ?? '',
        'birthday_client':
            Platform.environment['WHATSAPP_TEMPLATE_BIRTHDAY'] ?? '',
      },
    );
  } else if (config.automationProviderUrl != null &&
      config.automationProviderToken != null) {
    sender = HttpAutomationMessageSender(
      endpoint: Uri.parse(config.automationProviderUrl!),
      token: config.automationProviderToken!,
    );
  } else {
    sender = const DisabledAutomationMessageSender();
  }
  final automationEngine = MessageAutomationEngine(
    store: automations,
    sender: sender,
    publicBaseUrl: config.publicBaseUrl,
  );
  await store.ping();

  final api = StudioFlowApi(
    store: store,
    marketplace: marketplace,
    automations: automations,
    catalog: catalog,
    config: config,
  );
  final server = await shelf_io.serve(
    api.handler,
    InternetAddress.anyIPv4,
    config.port,
    shared: true,
  );
  server.autoCompress = true;
  automationEngine.start();
  stdout.writeln(
    'StudioFlow API em http://${server.address.host}:${server.port}',
  );

  var closing = false;
  Future<void> close() async {
    if (closing) return;
    closing = true;
    await server.close(force: false);
    await automationEngine.stop();
    await automations.close();
    await catalogStore.close();
    await marketplace.close();
    await store.close();
  }

  ProcessSignal.sigint.watch().listen((_) => unawaited(close()));
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) => unawaited(close()));
  }
}
