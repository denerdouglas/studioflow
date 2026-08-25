import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:studioflow_backend/studioflow_backend.dart';
import 'package:studioflow_backend/src/academy_memory_store.dart';

// Usamos instâncias tipadas null para serviços não requisitados pelo app-config.
void main() {
  test(
    'Endpoint /api/v1/public/app-config retorna 200 e json valido sem exigir autenticacao',
    () async {
      final config1 = BackendConfig(
        databaseUrl: 'postgres://postgres:postgres@localhost:5432/postgres',
        jwtSecret: '0' * 64,
        port: 8080,
        publicBaseUrl: Uri.parse('http://localhost:8080'),
        accessTokenDuration: const Duration(minutes: 15),
        refreshTokenDuration: const Duration(days: 30),
        uploadDirectory: 'storage',
        uploadMaxBytes: 10485760,
        catalogBaseUrl: Uri.parse('https://world.openfoodfacts.org'),
        whatsappGraphApiVersion: 'v23.0',
        appLatestBuild: 4053,
        appLatestVersion: '1.4.11',
        appMinBuild: 4050,
        appForceUpdate: false,
        appStoreUrl:
            'https://play.google.com/store/apps/details?id=com.rolgsystems.studioflow',
        appUpdateMessage: 'Nova atualização disponível',
      );

      // Bypassing dependencies for isolated endpoint test
      final api1 = StudioFlowApi(
        store: MemoryBackendStore(),
        config: config1,
        marketplace: MarketplaceService(MemoryBackendStore()),
        adminService: MarketplaceAdminService(MemoryBackendStore()),
        academy: AcademyService(AcademyMemoryStore()),
        secureRedirect: SecureRedirectService(AcademyMemoryStore()),
      );

      final request = Request(
        'GET',
        Uri.parse('http://localhost:8080/v1/public/app-config'),
      );
      final response = await api1.handler(request);

      expect(response.statusCode, equals(200));
      expect(response.headers['content-type'], contains('application/json'));

      final bodyStr = await response.readAsString();
      final json = jsonDecode(bodyStr);

      expect(json.containsKey('android'), isTrue);
      final android = json['android'];
      expect(android['latest_build'], equals(4053));
      expect(android['min_build'], equals(4050));
      expect(android['latest_version'], equals('1.4.11'));
      expect(android['force_update'], isFalse);
      expect(
        android['store_url'],
        equals(
          'https://play.google.com/store/apps/details?id=com.rolgsystems.studioflow',
        ),
      );

      // Nao vaza config de DB
      expect(bodyStr.contains('postgres'), isFalse);
    },
  );

  test('Alteracao de variaveis reflete dinamicamente na API', () async {
    final config2 = BackendConfig(
      databaseUrl: 'postgres://postgres:postgres@localhost:5432/postgres',
      jwtSecret: '0' * 64,
      port: 8080,
      publicBaseUrl: Uri.parse('http://localhost:8080'),
      accessTokenDuration: const Duration(minutes: 15),
      refreshTokenDuration: const Duration(days: 30),
      uploadDirectory: 'storage',
      uploadMaxBytes: 10485760,
      catalogBaseUrl: Uri.parse('https://world.openfoodfacts.org'),
      whatsappGraphApiVersion: 'v23.0',
      appLatestBuild: 4060,
      appLatestVersion: '2.0.0',
      appMinBuild: 4055,
      appForceUpdate: true,
      appStoreUrl: 'https://store.url',
      appUpdateMessage: 'Urgente',
    );

    final api2 = StudioFlowApi(
      store: MemoryBackendStore(),
      config: config2,
      marketplace: MarketplaceService(MemoryBackendStore()),
      adminService: MarketplaceAdminService(MemoryBackendStore()),
      academy: AcademyService(AcademyMemoryStore()),
      secureRedirect: SecureRedirectService(AcademyMemoryStore()),
    );

    final request = Request(
      'GET',
      Uri.parse('http://localhost:8080/v1/public/app-config'),
    );
    final response = await api2.handler(request);
    final json = jsonDecode(await response.readAsString());

    final android = json['android'];
    expect(android['latest_build'], equals(4060));
    expect(android['min_build'], equals(4055));
    expect(android['force_update'], isTrue);
  });
}
