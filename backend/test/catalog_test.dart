import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:studioflow_backend/studioflow_backend.dart';
import 'package:test/test.dart';

void main() {
  test(
    'consulta Open Facts pelo backend, preenche dados e usa cache',
    () async {
      var calls = 0;
      final store = MemoryCatalogStore();
      final service = CatalogLookupService(
        store: store,
        baseUrl: Uri.parse('https://world.openfoodfacts.org'),
        userAgent: 'StudioFlow/Test (test@studioflow.invalid)',
        client: MockClient((request) async {
          calls++;
          expect(request.headers['user-agent'], contains('StudioFlow'));
          expect(request.url.queryParameters['product_type'], 'all');
          return http.Response(
            jsonEncode({
              'product': {
                'product_name_pt': 'Creme profissional',
                'brands': 'Marca Teste',
                'categories': 'Cuidados capilares',
                'generic_name_pt': 'Máscara hidratante',
                'quantity': '300 ml',
                'image_front_url': 'https://images.test/produto.jpg',
              },
            }),
            200,
          );
        }),
      );

      final first = await service.lookup(
        businessId: 'business-1',
        userId: 'user-1',
        gtin: '3017620422003',
      );
      final second = await service.lookup(
        businessId: 'business-1',
        userId: 'user-1',
        gtin: '3017620422003',
      );
      expect(first?.name, 'Creme profissional');
      expect(first?.quantity, '300 ml');
      expect(second?.name, first?.name);
      expect(calls, 1);
      expect(store.logs.last['result'], 'found');
    },
  );

  test('distingue produto ausente de indisponibilidade da fonte', () async {
    final missingStore = MemoryCatalogStore();
    final missing = CatalogLookupService(
      store: missingStore,
      baseUrl: Uri.parse('https://world.openfoodfacts.org'),
      userAgent: 'StudioFlow/Test (test@studioflow.invalid)',
      client: MockClient((_) async => http.Response('{}', 404)),
    );
    expect(
      await missing.lookup(
        businessId: 'business-1',
        userId: 'user-1',
        gtin: '3017620422003',
      ),
      isNull,
    );
    expect(missingStore.logs.last['result'], 'not_found');

    final unavailableStore = MemoryCatalogStore();
    final unavailable = CatalogLookupService(
      store: unavailableStore,
      baseUrl: Uri.parse('https://world.openfoodfacts.org'),
      userAgent: 'StudioFlow/Test (test@studioflow.invalid)',
      client: MockClient((_) async => http.Response('{}', 503)),
    );
    await expectLater(
      unavailable.lookup(
        businessId: 'business-1',
        userId: 'user-1',
        gtin: '3017620422003',
      ),
      throwsStateError,
    );
    expect(unavailableStore.logs.last['result'], 'provider_error');
  });
}
