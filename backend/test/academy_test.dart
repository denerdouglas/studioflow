import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:studioflow_backend/studioflow_backend.dart';
import 'package:studioflow_backend/src/academy_memory_store.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

void main() {
  const jwtSecret =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
  late MemoryBackendStore store;
  late AcademyMemoryStore academyStore;
  late Handler handler;
  late String accessToken;
  final uuid = const Uuid();

  setUp(() async {
    store = MemoryBackendStore();
    academyStore = AcademyMemoryStore();
    final config = BackendConfig.fromEnvironment({
      'DATABASE_URL': 'postgresql://unused/test',
      'JWT_SECRET': jwtSecret,
      'PUBLIC_BASE_URL': 'https://api.studioflow.test',
    });

    // Seed some basic data
    final catGestao = AcademyCategory(
      id: uuid.v4(),
      name: 'Gestão',
      displayOrder: 1,
      createdAt: DateTime.now().toUtc(),
    );

    final partnerHotmart = 'hotmart_id';
    final partnerInactive = 'inactive_id';

    final courseGestao = AcademyCourse(
      id: uuid.v4(),
      title: 'Gestão de Salão 360',
      partnerId: partnerHotmart,
      categoryId: catGestao.id,
      sourceType: 'partner',
      publicationStatus: 'published',
      priceCents: 29900,
      currency: 'BRL',
      rating: 4.8,
      reviewsCount: 150,
      redirectUrl: 'https://hotmart.com/pt-br/checkout/abc',
    );

    final courseSemPreco = AcademyCourse(
      id: uuid.v4(),
      title: 'Curso Grátis ou Consulta',
      partnerId: partnerHotmart,
      categoryId: catGestao.id,
      sourceType: 'partner',
      publicationStatus: 'published',
      redirectUrl: 'https://hotmart.com/pt-br/checkout/free',
    );

    final courseComingSoon = AcademyCourse(
      id: uuid.v4(),
      title: 'Método StudioFlow',
      partnerId: partnerHotmart,
      categoryId: catGestao.id,
      sourceType: 'studioflow',
      publicationStatus: 'coming_soon',
    );

    final courseSuspended = AcademyCourse(
      id: uuid.v4(),
      title: 'Curso Suspenso',
      partnerId: partnerHotmart,
      categoryId: catGestao.id,
      sourceType: 'partner',
      publicationStatus: 'suspended',
    );

    final courseInactivePartner = AcademyCourse(
      id: uuid.v4(),
      title: 'Curso Inativo Parceiro',
      partnerId: partnerInactive,
      categoryId: catGestao.id,
      sourceType: 'partner',
      publicationStatus: 'published',
      redirectUrl: 'https://hotmart.com/pt-br/checkout/inactive',
    );

    final courseMalicious = AcademyCourse(
      id: uuid.v4(),
      title: 'Curso Malicioso',
      partnerId: partnerHotmart,
      categoryId: catGestao.id,
      sourceType: 'partner',
      publicationStatus: 'published',
      redirectUrl: 'http://localhost:8080/hack',
    );

    final courseExpiredCampaign = AcademyCourse(
      id: uuid.v4(),
      title: 'Curso Campanha Expirada',
      partnerId: partnerHotmart,
      categoryId: catGestao.id,
      sourceType: 'partner',
      publicationStatus: 'published',
      redirectUrl: 'https://hotmart.com/pt-br/checkout/expired',
    );

    academyStore.seedAcademy(
      [catGestao],
      [
        courseGestao,
        courseSemPreco,
        courseComingSoon,
        courseSuspended,
        courseInactivePartner,
        courseMalicious,
        courseExpiredCampaign,
      ],
      {partnerHotmart: 'hotmart', partnerInactive: 'inactive'},
      {partnerHotmart: true, partnerInactive: false},
      {'camp_expired': false},
    );

    handler = StudioFlowApi(
      store: store,
      marketplace: MarketplaceService(store),
      adminService: MarketplaceAdminService(store),
      academy: AcademyService(academyStore),
      secureRedirect: SecureRedirectService(academyStore),
      config: config,
    ).handler;

    // Simulate login for tests (fast way)
    final tokens = TokenSecurity(
      secret: jwtSecret,
      accessDuration: const Duration(hours: 1),
    );
    accessToken = tokens.createAccessToken(
      const AuthContext(
        userId: 'test-user',
        businessId: 'test-business',
        role: 'dono',
        sessionId: 'test-session',
      ),
    );
  });

  Future<Response> callApi(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final request = Request(
      method,
      Uri.parse('https://api.studioflow.test$path'),
      body: body != null ? jsonEncode(body) : null,
      headers: {
        if (body != null) 'content-type': 'application/json',
        if (token != null) 'authorization': 'Bearer $token',
      },
    );
    return handler(request);
  }

  test('GET /v1/academy/categories returns categories', () async {
    final response = await callApi(
      'GET',
      '/v1/academy/categories',
      token: accessToken,
    );
    expect(response.statusCode, 200);
    final json = jsonDecode(await response.readAsString());
    expect(json['categories'], isNotEmpty);
    expect(json['categories'][0]['name'], 'Gestão');
  });

  test(
    'GET /v1/academy/search with no query returns all published/coming_soon courses',
    () async {
      final response = await callApi(
        'GET',
        '/v1/academy/search',
        token: accessToken,
      );
      expect(response.statusCode, 200);
      final json = jsonDecode(await response.readAsString());
      expect(json['total'], 6); // Suspended is hidden
      final titles = (json['courses'] as List).map((c) => c['title']).toList();
      expect(titles, contains('Gestão de Salão 360'));
      expect(titles, contains('Método StudioFlow'));
      expect(titles, isNot(contains('Curso Suspenso')));
    },
  );

  test('GET /v1/academy/search with query filters correctly', () async {
    final response = await callApi(
      'GET',
      '/v1/academy/search?q=Gestão',
      token: accessToken,
    );
    expect(response.statusCode, 200);
    final json = jsonDecode(await response.readAsString());
    expect(json['total'], 1);
    expect(json['courses'][0]['title'], 'Gestão de Salão 360');
  });

  test('Course without price or rating does not return 0', () async {
    final response = await callApi(
      'GET',
      '/v1/academy/search?q=Grátis',
      token: accessToken,
    );
    final json = jsonDecode(await response.readAsString());
    final course = json['courses'][0];
    expect(course.containsKey('price'), isFalse);
    expect(course.containsKey('rating'), isFalse);
  });

  test('Coming soon course does not have clickId', () async {
    final response = await callApi(
      'GET',
      '/v1/academy/search?q=Método',
      token: accessToken,
    );
    final json = jsonDecode(await response.readAsString());
    final course = json['courses'][0];
    expect(course['publicationStatus'], 'coming_soon');
    expect(course.containsKey('clickId'), isFalse);
  });

  test('Published course with active partner has clickId', () async {
    final response = await callApi(
      'GET',
      '/v1/academy/search?q=Gestão',
      token: accessToken,
    );
    final json = jsonDecode(await response.readAsString());
    final course = json['courses'][0];
    expect(course['publicationStatus'], 'published');
    expect(course['clickId'], isNotNull);
  });

  test('Published course with inactive partner has no clickId', () async {
    final response = await callApi(
      'GET',
      '/v1/academy/search?q=Inativo',
      token: accessToken,
    );
    final json = jsonDecode(await response.readAsString());
    final course = json['courses'][0];
    expect(course['publicationStatus'], 'published');
    expect(course.containsKey('clickId'), isFalse);
  });

  test('Valid redirect works correctly', () async {
    final response = await callApi(
      'GET',
      '/v1/academy/search?q=Gestão',
      token: accessToken,
    );
    final json = jsonDecode(await response.readAsString());
    final clickId = json['courses'][0]['clickId'];

    final redirectResponse = await callApi('GET', '/academy/r/$clickId');
    expect(redirectResponse.statusCode, 302);
    expect(
      redirectResponse.headers['location'],
      'https://hotmart.com/pt-br/checkout/abc',
    );
  });

  test('Missing clickId returns error', () async {
    final redirectResponse = await callApi('GET', '/academy/r/null');
    expect(redirectResponse.statusCode, 400);
  });

  test('Invalid clickId returns error', () async {
    final redirectResponse = await callApi('GET', '/academy/r/ac_invalid123');
    expect(redirectResponse.statusCode, 400);
  });

  test('Repeated redirect returns error (click already used)', () async {
    final response = await callApi(
      'GET',
      '/v1/academy/search?q=Gestão',
      token: accessToken,
    );
    final json = jsonDecode(await response.readAsString());
    final clickId = json['courses'][0]['clickId'];

    await callApi('GET', '/academy/r/$clickId'); // First time works
    final second = await callApi(
      'GET',
      '/academy/r/$clickId',
    ); // Second time blocked
    expect(second.statusCode, 400);
  });

  test('Malicious redirect is blocked (HTTP/Localhost)', () async {
    final response = await callApi(
      'GET',
      '/v1/academy/search?q=Malicioso',
      token: accessToken,
    );
    final json = jsonDecode(await response.readAsString());
    final clickId = json['courses'][0]['clickId'];

    final redirectResponse = await callApi('GET', '/academy/r/$clickId');
    expect(redirectResponse.statusCode, 400);
    final errJson = jsonDecode(await redirectResponse.readAsString());
    expect(errJson['error']['message'], 'Destino inválido');
  });

  test('No secrets are returned in search', () async {
    final response = await callApi(
      'GET',
      '/v1/academy/search',
      token: accessToken,
    );
    final json = jsonDecode(await response.readAsString());
    final str = jsonEncode(json);
    expect(str.contains('secret'), isFalse);
    expect(str.contains('affiliateUrl'), isFalse);
  });
}
