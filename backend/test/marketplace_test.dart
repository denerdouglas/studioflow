import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:studioflow_backend/studioflow_backend.dart';
import 'package:test/test.dart';

void main() {
  late Handler handler;

  setUp(() {
    final store = MemoryBackendStore();
    final config = BackendConfig.fromEnvironment({
      'DATABASE_URL': 'postgresql://unused/test',
      'JWT_SECRET':
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      'PUBLIC_BASE_URL': 'https://api.studioflow.test',
      'ROLG_ADMIN_KEY': 'rolg-test-admin-key',
    });
    handler = StudioFlowApi(store: store, config: config).handler;
  });

  test('clique é registrado sem ser contado como conversão', () async {
    final registration =
        await _call(handler, 'POST', '/v1/auth/register-business', {
          'businessName': 'Studio Marketplace',
          'ownerName': 'Dona Studio',
          'phone': '5511999999999',
          'login': 'marketplace@studio.test',
          'password': 'senha-segura',
        });
    final token = registration.json['accessToken'] as String;
    final adminHeaders = {'x-rolg-admin-key': 'rolg-test-admin-key'};

    final program = await _call(
      handler,
      'PUT',
      '/v1/admin/affiliate/programs/mercado-livre',
      {
        'name': 'Mercado Livre',
        'enabled': true,
        'partnerId': 'parceiro-publico',
        'secretReference': 'vault://marketplace/ml',
        'allowedDomains': ['mercadolivre.com.br'],
        'disclosure': 'Este link pode gerar comissão ao StudioFlow.',
      },
      headers: adminHeaders,
    );
    expect(program.status, 200);
    expect(program.json['secretConfigured'], isTrue);
    expect(program.json, isNot(contains('secretReference')));

    await _call(handler, 'PUT', '/v1/admin/marketplace/offers/oferta-1', {
      'programId': 'mercado-livre',
      'title': 'Shampoo profissional 1L',
      'seller': 'Distribuidor verificado',
      'url': 'https://produto.mercadolivre.com.br/item-1',
      'priceCents': 4990,
      'shippingCents': 1000,
      'deliveryDays': 3,
    }, headers: adminHeaders);

    final search = await _call(
      handler,
      'GET',
      '/v1/marketplace/offers?q=shampoo',
      null,
      token: token,
    );
    expect(search.status, 200);
    expect(search.json['offers'], hasLength(1));

    final click = await _call(
      handler,
      'POST',
      '/v1/marketplace/offers/oferta-1/click',
      const {},
      token: token,
    );
    expect(click.status, 200);
    expect(click.json['affiliate'], isTrue);

    final metrics = await _call(
      handler,
      'GET',
      '/v1/admin/affiliate/metrics',
      null,
      headers: adminHeaders,
    );
    expect(metrics.json['clicks'], 1);
    expect(metrics.json['conversions'], 0);
  });
}

Future<ApiResponse> _call(
  Handler handler,
  String method,
  String path,
  Map<String, Object?>? body, {
  String? token,
  Map<String, String> headers = const {},
}) async {
  final response = await handler(
    Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: {
        if (body != null) 'content-type': 'application/json',
        if (token != null) 'authorization': 'Bearer $token',
        ...headers,
      },
      body: body == null ? null : jsonEncode(body),
    ),
  );
  final content = await response.readAsString();
  return ApiResponse(
    response.statusCode,
    content.isEmpty
        ? const {}
        : Map<String, dynamic>.from(jsonDecode(content) as Map),
  );
}

final class ApiResponse {
  final int status;
  final Map<String, dynamic> json;
  const ApiResponse(this.status, this.json);
}
