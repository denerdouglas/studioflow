import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:studioflow_backend/studioflow_backend.dart';
import 'package:studioflow_backend/src/academy_memory_store.dart';
import 'package:test/test.dart';

void main() {
  const secret =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
  late MemoryBackendStore backend;
  late GlobalContentMemoryStore content;
  late CommercialCampaignMemoryStore campaignStore;
  late Handler handler;

  setUp(() async {
    backend = MemoryBackendStore();
    content = GlobalContentMemoryStore();
    campaignStore = CommercialCampaignMemoryStore();
    final academy = AcademyMemoryStore();
    handler = StudioFlowApi(
      store: backend,
      config: BackendConfig.fromEnvironment({
        'DATABASE_URL': 'postgresql://unused/test',
        'JWT_SECRET': secret,
        'PUBLIC_BASE_URL': 'https://api.studioflow.test',
      }),
      marketplace: MarketplaceService(backend),
      adminService: MarketplaceAdminService(backend),
      academy: AcademyService(academy),
      secureRedirect: SecureRedirectService(academy),
      campaigns: CommercialCampaignService(campaignStore),
      globalContent: content,
    ).handler;
    await backend.createBusinessOwner(
      businessId: 'business-admin',
      businessName: 'ROLG',
      segment: 'outros',
      userId: 'user-admin',
      ownerName: 'Admin',
      phone: '11999999999',
      login: 'dener.douglas2015@outlook.com',
      passwordHash: const PasswordSecurity().hash('senha-segura'),
    );
    await backend.createBusinessOwner(
      businessId: 'business-user',
      businessName: 'Studio',
      segment: 'manicure',
      userId: 'user-common',
      ownerName: 'Comum',
      phone: '11888888888',
      login: 'comum@teste.com',
      passwordHash: const PasswordSecurity().hash('senha-segura'),
    );
  });

  Future<(int, Map<String, dynamic>)> call(
    String method,
    String path, {
    String? token,
    Map<String, Object?>? body,
  }) async {
    final response = await handler(
      Request(
        method,
        Uri.parse('https://api.studioflow.test$path'),
        headers: {
          if (token != null) 'authorization': 'Bearer $token',
          if (body != null) 'content-type': 'application/json',
        },
        body: body == null ? null : jsonEncode(body),
      ),
    );
    final text = await response.readAsString();
    return (
      response.statusCode,
      text.isEmpty
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(text) as Map),
    );
  }

  Future<String> login(String email) async {
    final result = await call(
      'POST',
      '/v1/auth/login',
      body: {'login': email, 'password': 'senha-segura'},
    );
    return result.$2['accessToken'] as String;
  }

  test('usuário comum recebe 403 em endpoint administrativo', () async {
    final token = await login('comum@teste.com');
    expect(
      (await call(
        'GET',
        '/v1/platform-admin/global-products',
        token: token,
      )).$1,
      403,
    );
  });

  test('super admin armazenado no backend recebe acesso', () async {
    backend.seedPlatformAdmin(
      PlatformAdmin(
        id: 'admin-id',
        userId: 'user-admin',
        role: 'platform_super_admin',
        active: true,
        permissions: const {},
        createdAt: DateTime.now().toUtc(),
      ),
    );
    final token = await login('dener.douglas2015@outlook.com');
    expect(
      (await call(
        'GET',
        '/v1/platform-admin/global-products',
        token: token,
      )).$1,
      200,
    );
  });

  test(
    'email em payload não concede admin e revogação remove acesso',
    () async {
      final common = await login('comum@teste.com');
      expect(
        (await call(
          'POST',
          '/v1/platform-admin/global-products',
          token: common,
          body: {
            'email': 'dener.douglas2015@outlook.com',
            'businessId': 'business-admin',
          },
        )).$1,
        403,
      );
      backend.seedPlatformAdmin(
        PlatformAdmin(
          id: 'admin-id',
          userId: 'user-admin',
          role: 'platform_super_admin',
          active: true,
          permissions: const {},
          createdAt: DateTime.now().toUtc(),
        ),
      );
      final token = await login('dener.douglas2015@outlook.com');
      backend.revokePlatformAdmin('user-admin');
      expect(
        (await call(
          'GET',
          '/v1/platform-admin/global-products',
          token: token,
        )).$1,
        403,
      );
    },
  );

  test(
    'barcode é normalizado, conhecido retorna e duplicado é impedido',
    () async {
      final now = DateTime.now().toUtc();
      final product = GlobalProduct(
        id: 'product-1',
        barcode: normalizeBarcode('789-49000-1151-7'),
        brand: 'Impala',
        name: 'Esmalte',
        category: 'Esmaltes',
        active: true,
        verified: true,
        createdBy: 'admin',
        createdAt: now,
        updatedAt: now,
      );
      await content.saveProduct(product);
      expect(
        (await content.productByBarcode('7894900011517'))?.name,
        'Esmalte',
      );
      expect(await content.productByBarcode('0000000000000'), isNull);
      expect(
        () => content.saveProduct(
          GlobalProduct(
            id: 'product-2',
            barcode: product.barcode,
            brand: 'Outra',
            name: 'Outro',
            category: 'Outros',
            active: true,
            verified: true,
            createdBy: 'admin',
            createdAt: now,
            updatedAt: now,
          ),
        ),
        throwsStateError,
      );
    },
  );

  test('validação global cobre GTIN-8, UPC-A, EAN-13 e GTIN-14', () {
    expect(isValidGlobalBarcode('96385074'), isTrue);
    expect(isValidGlobalBarcode('036000291452'), isTrue);
    expect(isValidGlobalBarcode('7894900011517'), isTrue);
    expect(isValidGlobalBarcode('10012345000017'), isTrue);
    expect(isValidGlobalBarcode('789-49000-1151-7'), isTrue);
    expect(isValidGlobalBarcode('7894900011518'), isFalse);
    expect(isValidGlobalBarcode('ABC-526839'), isFalse);
  });

  test('sugestão fica pendente, rejeição não publica', () async {
    final token = await login('comum@teste.com');
    final created = await call(
      'POST',
      '/v1/global-products/suggestions',
      token: token,
      body: {'barcode': '7894900011517', 'name': 'Esmalte'},
    );
    expect(created.$1, 201);
    expect(await content.productByBarcode('7894900011517'), isNull);
    expect((created.$2['suggestion'] as Map)['status'], 'pending');
  });

  test('aprovação admin publica e rejeição preserva ausência', () async {
    backend.seedPlatformAdmin(
      PlatformAdmin(
        id: 'admin-id',
        userId: 'user-admin',
        role: 'platform_super_admin',
        active: true,
        permissions: const {},
        createdAt: DateTime.now().toUtc(),
      ),
    );
    final common = await login('comum@teste.com');
    final admin = await login('dener.douglas2015@outlook.com');
    final first = await call(
      'POST',
      '/v1/global-products/suggestions',
      token: common,
      body: {'barcode': '7894900011517', 'name': 'Esmalte', 'brand': 'Impala'},
    );
    final firstId = (first.$2['suggestion'] as Map)['id'] as String;
    expect(
      (await call(
        'POST',
        '/v1/platform-admin/product-suggestions/$firstId/approve',
        token: admin,
      )).$1,
      200,
    );
    expect(await content.productByBarcode('7894900011517'), isNotNull);

    final second = await call(
      'POST',
      '/v1/global-products/suggestions',
      token: common,
      body: {'barcode': '4006381333931', 'name': 'Outro'},
    );
    final secondId = (second.$2['suggestion'] as Map)['id'] as String;
    await call(
      'POST',
      '/v1/platform-admin/product-suggestions/$secondId/reject',
      token: admin,
    );
    expect(await content.productByBarcode('4006381333931'), isNull);
    expect((await content.suggestionById(secondId))?.reviewedBy, 'user-admin');
    expect((await content.suggestionById(secondId))?.reviewedAt, isNotNull);
  });

  test('busca de curso usa título e keywords e omite inativo', () async {
    final now = DateTime.now().toUtc();
    await content.saveCourse(
      GlobalCourse(
        id: 'welding',
        title: 'Curso Profissional',
        provider: 'Parceiro',
        description: 'Capacitação',
        category: 'Solda',
        keywords: const ['mig', 'tig'],
        active: true,
        createdBy: 'admin',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await content.saveCourse(
      GlobalCourse(
        id: 'inactive',
        title: 'Solda antiga',
        provider: 'X',
        description: 'X',
        category: 'Solda',
        active: false,
        createdBy: 'admin',
        createdAt: now,
        updatedAt: now,
      ),
    );
    for (final query in ['curso', 'parceiro', 'capacitação', 'solda', 'TIG']) {
      expect(
        (await content.searchCourses(query)).map((item) => item.id),
        ['welding'],
        reason: 'query=$query',
      );
    }
  });

  test('curso e produto continuam válidos sem campanha', () async {
    final now = DateTime.now().toUtc();
    await content.saveCourse(
      GlobalCourse(
        id: 'course',
        title: 'Excel',
        provider: 'ROLG',
        description: 'Planilhas',
        category: 'Informática',
        active: true,
        createdBy: 'admin',
        createdAt: now,
        updatedAt: now,
      ),
    );
    expect(
      (await content.searchCourses('excel')).single.toJson()['campaign'],
      isNull,
    );
  });

  test('produto global pesquisa campos escalares e search_keywords', () async {
    final now = DateTime.now().toUtc();
    await content.saveProduct(
      GlobalProduct(
        id: 'product-search',
        barcode: '7894900011517',
        brand: 'Impala',
        name: 'Esmalte Cremoso',
        variant: 'Rosa antigo',
        category: 'Unhas',
        description: 'Acabamento brilhante',
        keywords: const ['manicure', 'verniz'],
        active: true,
        verified: true,
        createdBy: 'admin',
        createdAt: now,
        updatedAt: now,
      ),
    );

    for (final query in [
      'esmalte',
      'impala',
      'unhas',
      'brilhante',
      'rosa',
      'verniz',
    ]) {
      expect(
        (await content.listProducts(query: query)).map((item) => item.id),
        ['product-search'],
        reason: 'query=$query',
      );
    }
  });

  test('curso e produto expõem somente campanha ativa relacionada', () async {
    final token = await login('comum@teste.com');
    final now = DateTime.now().toUtc();
    await content.saveCourse(
      GlobalCourse(
        id: 'solda',
        title: 'Curso de Solda Profissional',
        provider: 'Parceiro',
        description: 'Solda MIG e TIG',
        category: 'Solda',
        keywords: const ['soldador', 'mig', 'tig'],
        active: true,
        createdBy: 'admin',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await content.saveProduct(
      GlobalProduct(
        id: 'esmalte',
        barcode: '7894900011517',
        brand: 'Impala',
        name: 'Esmalte',
        category: 'Esmaltes',
        active: true,
        verified: true,
        createdBy: 'admin',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await campaignStore.saveCampaign(
      CommercialCampaign(
        id: 'course-offer',
        title: 'Oferta Solda',
        description: 'Parceiro',
        destinationUrl: 'https://parceiro.test/solda',
        category: 'Cursos',
        sourceType: 'affiliate',
        ctaText: 'Ver curso',
        priority: 10,
        active: true,
        courseId: 'solda',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await campaignStore.saveCampaign(
      CommercialCampaign(
        id: 'expired-product',
        title: 'Oferta antiga',
        description: 'Expirada',
        destinationUrl: 'https://parceiro.test/esmalte',
        category: 'Produtos',
        sourceType: 'affiliate',
        ctaText: 'Ver oferta',
        priority: 10,
        active: true,
        globalProductId: 'esmalte',
        endsAt: now.subtract(const Duration(minutes: 1)),
        createdAt: now,
        updatedAt: now,
      ),
    );

    final courses = await call(
      'GET',
      '/v1/global-courses?q=solda',
      token: token,
    );
    final course = (courses.$2['courses'] as List).single as Map;
    final campaign = course['campaign'] as Map;
    expect(campaign['sourceType'], 'affiliate');
    expect(campaign['destinationUrl'], 'https://parceiro.test/solda');
    expect(campaign['courseId'], 'solda');

    final product = await call(
      'GET',
      '/v1/global-products/barcode/7894900011517',
      token: token,
    );
    expect(product.$1, 200);
    expect((product.$2['product'] as Map).containsKey('cost'), isFalse);
    expect((product.$2['product'] as Map).containsKey('stock'), isFalse);
    expect(product.$2.containsKey('campaign'), isFalse);
  });

  test('admin mantém identidade do produto ao atualizar', () async {
    backend.seedPlatformAdmin(
      PlatformAdmin(
        id: 'admin-id',
        userId: 'user-admin',
        role: 'platform_super_admin',
        active: true,
        permissions: const {},
        createdAt: DateTime.now().toUtc(),
      ),
    );
    final admin = await login('dener.douglas2015@outlook.com');
    final created = await call(
      'POST',
      '/v1/platform-admin/global-products',
      token: admin,
      body: {
        'barcode': '7894900011517',
        'brand': 'Impala',
        'name': 'Esmalte',
        'category': 'Esmaltes',
      },
    );
    final id = (created.$2['product'] as Map)['id'];
    final updated = await call(
      'POST',
      '/v1/platform-admin/global-products',
      token: admin,
      body: {
        'id': id,
        'barcode': '7894900011517',
        'brand': 'Impala',
        'name': 'Esmalte Rosa',
        'category': 'Esmaltes',
      },
    );
    expect(updated.$1, 200);
    expect((updated.$2['product'] as Map)['id'], id);
    expect((await content.listProducts()), hasLength(1));
  });

  test('admin persiste created_by obrigatório ao criar curso', () async {
    backend.seedPlatformAdmin(
      PlatformAdmin(
        id: 'admin-id',
        userId: 'user-admin',
        role: 'platform_super_admin',
        active: true,
        permissions: const {},
        createdAt: DateTime.now().toUtc(),
      ),
    );
    final admin = await login('dener.douglas2015@outlook.com');
    final response = await call(
      'POST',
      '/v1/platform-admin/global-courses',
      token: admin,
      body: {
        'title': 'Curso de Solda',
        'provider': 'Parceiro',
        'description': 'MIG e TIG',
        'category': 'Solda',
        'keywords': ['solda'],
      },
    );
    expect(response.$1, 201);
    final id = (response.$2['course'] as Map)['id'] as String;
    expect((await content.courseById(id))?.createdBy, 'user-admin');

    final inactive = await call(
      'POST',
      '/v1/platform-admin/global-courses',
      token: admin,
      body: {
        'title': 'Curso inativo',
        'provider': 'Parceiro',
        'description': 'Arquivado',
        'category': 'Outros',
        'active': false,
      },
    );
    expect(inactive.$1, 201);
    final adminList = await call(
      'GET',
      '/v1/platform-admin/global-courses',
      token: admin,
    );
    expect((adminList.$2['courses'] as List), hasLength(2));
    final publicList = await call('GET', '/v1/global-courses', token: admin);
    expect((publicList.$2['courses'] as List), hasLength(1));
  });
}
