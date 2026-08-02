import 'package:uuid/uuid.dart';

final class MarketplacePartner {
  final String id;
  final String slug;
  final String name;
  final String? logo;
  final String partnerType;
  final String status;
  final int priority;
  final String? affiliateIdentifier;
  final String? urlTemplate;
  final bool supportsSearch;
  final bool supportsDeepLink;
  final bool supportsConversion;
  final String? secretEncrypted;
  final String? secretKeyVersion;
  final Map<String, dynamic> publicConfig;
  final String? notes;
  final DateTime createdAt;

  const MarketplacePartner({
    required this.id,
    required this.slug,
    required this.name,
    this.logo,
    required this.partnerType,
    required this.status,
    required this.priority,
    this.affiliateIdentifier,
    this.urlTemplate,
    required this.supportsSearch,
    required this.supportsDeepLink,
    required this.supportsConversion,
    this.secretEncrypted,
    this.secretKeyVersion,
    required this.publicConfig,
    this.notes,
    required this.createdAt,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'slug': slug,
    'name': name,
    'logo': logo,
    'partnerType': partnerType,
    'status': status,
    'priority': priority,
    'affiliateIdentifier': affiliateIdentifier,
    'urlTemplate': urlTemplate,
    'supportsSearch': supportsSearch,
    'supportsDeepLink': supportsDeepLink,
    'supportsConversion': supportsConversion,
    'publicConfig': publicConfig,
    'notes': notes,
    'createdAt': createdAt.toIso8601String(),
  };
}

final class MarketplacePartnerDomain {
  final String id;
  final String partnerId;
  final String hostname;
  final bool allowSubdomains;
  final bool active;
  final DateTime createdAt;

  const MarketplacePartnerDomain({
    required this.id,
    required this.partnerId,
    required this.hostname,
    required this.allowSubdomains,
    required this.active,
    required this.createdAt,
  });
}

final class MarketplaceClick {
  final String id; // UUIDv7
  final String? businessId;
  final String userId;
  final String partnerId;
  final String destinationUrl;
  final String clickStatus;
  final String? source;
  final String? campaignId;
  final String? userAgentHash;
  final String? ipHash;
  final int? rankingPosition;
  final String? rankingReason;
  final DateTime clickedAt;
  final DateTime? redirectedAt;
  final DateTime? expiresAt;

  const MarketplaceClick({
    required this.id,
    this.businessId,
    required this.userId,
    required this.partnerId,
    required this.destinationUrl,
    required this.clickStatus,
    this.source,
    this.campaignId,
    this.userAgentHash,
    this.ipHash,
    this.rankingPosition,
    this.rankingReason,
    required this.clickedAt,
    this.redirectedAt,
    this.expiresAt,
  });
}

abstract interface class MarketplaceBackendStore {
  Future<List<MarketplacePartner>> listActivePartners();
  Future<List<MarketplacePartner>> listAllPartners();
  Future<MarketplacePartner?> findPartnerById(String id);
  Future<void> savePartner(MarketplacePartner partner);
  
  Future<List<MarketplacePartnerDomain>> listDomainsForPartner(String partnerId);
  Future<void> saveDomain(MarketplacePartnerDomain domain);

  Future<void> logSearch({
    required String? businessId,
    required String userId,
    required String query,
    required String source,
    required bool cacheHit,
    required int resultsCount,
    required int responseTimeMs,
  });

  Future<void> recordClick(MarketplaceClick click);
  Future<MarketplaceClick?> findClick(String id);
  Future<void> updateClickStatus(String id, String status, {DateTime? redirectedAt});
  
  Future<void> auditAdminAction({
    required String platformAdminId,
    required String action,
    required String entity,
    required String entityId,
    Map<String, dynamic>? beforeState,
    Map<String, dynamic>? afterState,
    String? reason,
    String? ipAddressHash,
  });
}

class MarketplaceService {
  final MarketplaceBackendStore _store;

  MarketplaceService(this._store);

    Future<List<MarketplacePartner>> listAllPartners() => _store.listAllPartners();
  
  Future<void> logSearch({
    required String? businessId,
    required String userId,
    required String query,
    required String source,
    required bool cacheHit,
    required int resultsCount,
    required int responseTimeMs,
  }) => _store.logSearch(
    businessId: businessId,
    userId: userId,
    query: query,
    source: source,
    cacheHit: cacheHit,
    resultsCount: resultsCount,
    responseTimeMs: responseTimeMs,
  );

  Future<String> generateRedirectUrl({
    required String userId,
    required String? businessId,
    required String partnerId,
    required String destinationUrl,
    String? source,
    String? campaignId,
    String? userAgentHash,
    String? ipHash,
    int? rankingPosition,
    String? rankingReason,
  }) async {
    // 1. Validate Partner exists and is active
    final partner = await _store.findPartnerById(partnerId);
    if (partner == null || partner.status != 'active') {
      throw Exception('Parceiro inválido ou inativo.');
    }

    // 2. Validate Domain (allowlist)
    final uri = Uri.tryParse(destinationUrl);
    if (uri == null || uri.scheme != 'https') {
      throw Exception('URL de destino inválida ou esquema não seguro.');
    }
    if (uri.userInfo.isNotEmpty) {
      throw Exception('URL com credenciais não é permitida.');
    }
    
    // Check against allowlist
    final domains = await _store.listDomainsForPartner(partnerId);
    bool isAllowed = false;
    for (final domain in domains) {
      if (!domain.active) continue;
      if (domain.hostname == uri.host) {
        isAllowed = true;
        break;
      }
      if (domain.allowSubdomains && uri.host.endsWith('.${domain.hostname}')) {
        isAllowed = true;
        break;
      }
    }
    if (!isAllowed) {
      throw Exception('Domínio não autorizado para este parceiro.');
    }

    // 3. Create Click UUIDv7 (approximate using timestamp + random for now, or true v7 if available)
    // dart uuid package supports v7
    final clickId = const Uuid().v7();
    
    // 4. Record Click
    final click = MarketplaceClick(
      id: clickId,
      businessId: businessId,
      userId: userId,
      partnerId: partnerId,
      destinationUrl: destinationUrl,
      clickStatus: 'created',
      source: source,
      campaignId: campaignId,
      userAgentHash: userAgentHash,
      ipHash: ipHash,
      rankingPosition: rankingPosition,
      rankingReason: rankingReason,
      clickedAt: DateTime.now().toUtc(),
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    await _store.recordClick(click);

    return 'https://api.studioflowapp.com.br/r/$clickId';
  }

  Future<String> resolveRedirect(String clickId) async {
    final click = await _store.findClick(clickId);
    if (click == null) {
      throw Exception('Link não encontrado.');
    }
    if (click.clickStatus != 'created') {
      throw Exception('Link já utilizado ou inválido.');
    }
    if (click.expiresAt != null && DateTime.now().toUtc().isAfter(click.expiresAt!)) {
      await _store.updateClickStatus(clickId, 'expired');
      throw Exception('Link expirado.');
    }

    final partner = await _store.findPartnerById(click.partnerId);
    if (partner == null || partner.status != 'active') {
      await _store.updateClickStatus(clickId, 'blocked');
      throw Exception('Parceiro indisponível.');
    }

    // Apply URL template if available
    String finalUrl = click.destinationUrl;
    if (partner.urlTemplate != null && partner.urlTemplate!.isNotEmpty) {
      finalUrl = partner.urlTemplate!
          .replaceAll('{dest}', Uri.encodeComponent(click.destinationUrl))
          .replaceAll('{id}', partner.affiliateIdentifier ?? '');
    }

    // Update status
    await _store.updateClickStatus(clickId, 'redirected', redirectedAt: DateTime.now().toUtc());

    return finalUrl;
  }
}
