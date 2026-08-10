import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:studioflow_backend/studioflow_backend.dart';
import 'package:studioflow_backend/src/academy_memory_store.dart';

void main() {
  group('Public Booking API - Tratamento de slug inválido', () {
    late MemoryBackendStore store;
    late Handler handler;

    setUp(() {
      store = MemoryBackendStore();
      final config = BackendConfig.fromEnvironment({
        'DATABASE_URL': 'postgresql://unused/test',
        'JWT_SECRET':
            '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        'PUBLIC_BASE_URL': 'https://api.studioflow.test',
      });
      handler = StudioFlowApi(
        store: store,
        marketplace: MarketplaceService(store),
        adminService: MarketplaceAdminService(store),
        academy: AcademyService(AcademyMemoryStore()),
        secureRedirect: SecureRedirectService(AcademyMemoryStore()),
        config: config,
      ).handler;
    });

    test('Deve retornar 404 para slug inexistente', () async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/v1/public/booking/slug-inexistente-123'),
      );
      final response = await handler(request);

      expect(response.statusCode, 404);
      final body = jsonDecode(await response.readAsString());
      expect(body['error']['code'], 'booking_not_found');
    });

    test('Deve retornar 404 para serviços de slug inexistente', () async {
      final request = Request(
        'GET',
        Uri.parse(
          'http://localhost/v1/public/booking/slug-inexistente-123/services',
        ),
      );
      final response = await handler(request);

      expect(response.statusCode, 404);
    });
  });
}
