import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:studioflow_backend/studioflow_backend.dart';
import 'package:studioflow_backend/src/academy_memory_store.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 5, 12);
  late CommercialCampaignMemoryStore store;
  late CommercialCampaignService service;

  CommercialCampaign campaign({
    required String id,
    String source = 'rolg_academy',
    bool active = true,
    int priority = 0,
    List<String> segments = const [],
    DateTime? startsAt,
    DateTime? endsAt,
    String url = 'https://academy.rolg.com/oferta',
  }) => CommercialCampaign(
    id: id,
    title: 'Oferta $id',
    description: 'Descrição',
    destinationUrl: url,
    category: 'curso',
    sourceType: source,
    ctaText: 'Conhecer',
    priority: priority,
    active: active,
    segments: segments,
    startsAt: startsAt,
    endsAt: endsAt,
    createdAt: now,
    updatedAt: now,
  );

  setUp(() {
    store = CommercialCampaignMemoryStore();
    service = CommercialCampaignService(store, now: () => now);
  });

  test('global aparece e segmento compatível aparece', () async {
    store.seed([
      campaign(id: 'global'),
      campaign(id: 'nails', segments: ['manicure']),
    ]);
    expect(
      (await service.available(segment: 'manicure')).map((e) => e.id),
      containsAll(['global', 'nails']),
    );
  });

  test('outro segmento não aparece e legacy recebe somente global', () async {
    store.seed([
      campaign(id: 'global'),
      campaign(id: 'barber', segments: ['barbearia']),
    ]);
    expect((await service.available(segment: 'manicure')).map((e) => e.id), [
      'global',
    ]);
    expect((await service.available()).map((e) => e.id), ['global']);
  });

  test('inativa, futura e expirada não aparecem', () async {
    store.seed([
      campaign(id: 'inactive', active: false),
      campaign(id: 'future', startsAt: now.add(const Duration(minutes: 1))),
      campaign(id: 'expired', endsAt: now),
      campaign(id: 'valid', endsAt: now.add(const Duration(minutes: 1))),
    ]);
    expect((await service.available()).map((e) => e.id), ['valid']);
  });

  test('ordena por prioridade e depois atualização', () async {
    store.seed([
      campaign(id: 'low', priority: 1),
      campaign(id: 'high', priority: 10),
    ]);
    expect((await service.available()).map((e) => e.id), ['high', 'low']);
  });

  test('validador aceita HTTPS e rejeita HTTP, esquemas e URLs inválidas', () {
    expect(CommercialCampaignService.isSafeHttps('https://rolg.com/x'), isTrue);
    expect(CommercialCampaignService.isSafeHttps('http://rolg.com/x'), isFalse);
    expect(
      CommercialCampaignService.isSafeHttps('javascript:alert(1)'),
      isFalse,
    );
    expect(CommercialCampaignService.isSafeHttps('não é url'), isFalse);
    expect(
      CommercialCampaignService.isSafeHttps('https://localhost/x'),
      isFalse,
    );
  });

  test('impression e click ficam associados ao tenant autenticado', () async {
    store.seed([campaign(id: 'one')]);
    const actor = AuthContext(
      userId: 'user-a',
      businessId: 'business-a',
      role: 'dono',
      sessionId: 'session-a',
    );
    await service.event(actor, 'one', 'impression');
    await service.event(actor, 'one', 'click');
    expect(store.events, hasLength(2));
    expect(store.events.every((e) => e['businessId'] == 'business-a'), isTrue);
    expect(store.events.map((e) => e['type']), ['impression', 'click']);
  });

  test('CTR pode ser calculado pelos eventos persistidos', () async {
    store.seed([campaign(id: 'one')]);
    const actor = AuthContext(
      userId: 'user-a',
      businessId: 'business-a',
      role: 'dono',
      sessionId: 'session-a',
    );
    await service.event(actor, 'one', 'impression');
    await service.event(actor, 'one', 'impression');
    await service.event(actor, 'one', 'click');
    final impressions = store.events
        .where((e) => e['type'] == 'impression')
        .length;
    final clicks = store.events.where((e) => e['type'] == 'click').length;
    expect(clicks / impressions, 0.5);
  });

  test('evento rejeita campanha indisponível e ator sem business_id', () async {
    store.seed([campaign(id: 'inactive', active: false)]);
    const noTenant = AuthContext(
      userId: 'admin',
      role: 'admin',
      sessionId: 'session',
    );
    expect(
      () => service.event(noTenant, 'inactive', 'impression'),
      throwsArgumentError,
    );
  });

  test('usuário comum não acessa administração de campanhas', () async {
    const secret =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
    final backend = MemoryBackendStore();
    final academyStore = AcademyMemoryStore();
    final handler = StudioFlowApi(
      store: backend,
      config: BackendConfig.fromEnvironment({
        'DATABASE_URL': 'postgresql://unused/test',
        'JWT_SECRET': secret,
        'PUBLIC_BASE_URL': 'https://api.studioflow.test',
      }),
      marketplace: MarketplaceService(backend),
      adminService: MarketplaceAdminService(backend),
      academy: AcademyService(academyStore),
      secureRedirect: SecureRedirectService(academyStore),
      campaigns: service,
    ).handler;
    final token =
        TokenSecurity(
          secret: secret,
          accessDuration: const Duration(hours: 1),
        ).createAccessToken(
          const AuthContext(
            userId: 'user-a',
            businessId: 'business-a',
            role: 'dono',
            sessionId: 'session-a',
          ),
        );
    final response = await handler(
      Request(
        'GET',
        Uri.parse('https://api.studioflow.test/v1/platform-admin/campaigns'),
        headers: {'authorization': 'Bearer $token'},
      ),
    );
    expect(response.statusCode, 403);
    final body = jsonDecode(await response.readAsString()) as Map;
    expect((body['error'] as Map)['code'], 'forbidden');
  });
}
