import 'package:studioflow_backend/studioflow_backend.dart';
import 'package:test/test.dart';

void main() {
  test(
    'catálogo afiliado pesquisa oferta ativa e gera redirect seguro',
    () async {
      final store = MemoryBackendStore();
      final service = MarketplaceService(store);
      final partner = MarketplacePartner(
        id: 'ml',
        slug: 'mercado-livre',
        name: 'Mercado Livre',
        partnerType: 'marketplace',
        status: 'active',
        priority: 10,
        supportsSearch: true,
        supportsDeepLink: true,
        supportsConversion: false,
        publicConfig: const {},
        createdAt: DateTime.utc(2026, 8, 3),
      );
      await store.savePartner(partner);
      await store.saveDomain(
        MarketplacePartnerDomain(
          id: 'domain-ml',
          partnerId: partner.id,
          hostname: 'mercadolivre.com.br',
          allowSubdomains: true,
          active: true,
          createdAt: DateTime.utc(2026, 8, 3),
        ),
      );
      await store.saveOffer(
        MarketplaceOffer(
          id: 'offer-1',
          partnerId: partner.id,
          title: 'Acetona profissional',
          seller: 'Loja parceira',
          destinationUrl: 'https://produto.mercadolivre.com.br/acetona',
          priceCents: 1990,
          active: true,
          verifiedAt: DateTime.utc(2026, 8, 3),
          category: 'unhas',
          keywords: const ['removedor'],
        ),
      );

      final offers = await service.searchOffers('acetona');
      expect(offers, hasLength(1));
      final redirect = await service.generateRedirectUrl(
        userId: 'user-1',
        businessId: 'business-1',
        partnerId: partner.id,
        destinationUrl: offers.single.destinationUrl,
        source: 'estoque_baixo',
      );
      expect(redirect, contains('/r/'));
    },
  );

  test(
    'open redirect é bloqueado e demanda sem resultado é contabilizada',
    () async {
      final store = MemoryBackendStore();
      final service = MarketplaceService(store);
      await store.savePartner(
        MarketplacePartner(
          id: 'partner',
          slug: 'partner',
          name: 'Parceiro',
          partnerType: 'marketplace',
          status: 'active',
          priority: 1,
          supportsSearch: true,
          supportsDeepLink: true,
          supportsConversion: false,
          publicConfig: const {},
          createdAt: DateTime.utc(2026, 8, 3),
        ),
      );
      await store.saveDomain(
        MarketplacePartnerDomain(
          id: 'domain',
          partnerId: 'partner',
          hostname: 'parceiro.test',
          allowSubdomains: false,
          active: true,
          createdAt: DateTime.utc(2026, 8, 3),
        ),
      );
      expect(
        () => service.generateRedirectUrl(
          userId: 'u',
          businessId: 'b',
          partnerId: 'partner',
          destinationUrl: 'https://evil.test/produto',
        ),
        throwsException,
      );
      await service.logSearch(
        businessId: 'b',
        userId: 'u',
        query: 'produto ausente',
        source: 'ia',
        cacheHit: false,
        resultsCount: 0,
        responseTimeMs: 1,
      );
      await service.logSearch(
        businessId: 'b',
        userId: 'u',
        query: 'produto ausente',
        source: 'ia',
        cacheHit: false,
        resultsCount: 0,
        responseTimeMs: 1,
      );
      expect((await service.listSearchDemands()).single['searchCount'], 2);
    },
  );
  test('oferta inativa não aparece', () async {
    final store = MemoryBackendStore();
    await store.savePartner(
      MarketplacePartner(
        id: 'shopee',
        slug: 'shopee',
        name: 'Shopee',
        partnerType: 'marketplace',
        status: 'active',
        priority: 1,
        supportsSearch: true,
        supportsDeepLink: true,
        supportsConversion: false,
        publicConfig: const {},
        createdAt: DateTime.utc(2026, 8, 3),
      ),
    );
    await store.saveOffer(
      MarketplaceOffer(
        id: 'inactive',
        partnerId: 'shopee',
        title: 'Luvas',
        seller: 'Parceiro',
        destinationUrl: 'https://shopee.com.br/luvas',
        active: false,
        verifiedAt: DateTime.utc(2026, 8, 3),
      ),
    );
    expect(await MarketplaceService(store).searchOffers('luvas'), isEmpty);
  });
}
