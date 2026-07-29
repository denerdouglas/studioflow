final class AffiliateProgram {
  final String id;
  final String name;
  final bool enabled;
  final String? partnerId;
  final String? secretReference;
  final List<String> allowedDomains;
  final String disclosure;

  const AffiliateProgram({
    required this.id,
    required this.name,
    required this.enabled,
    this.partnerId,
    this.secretReference,
    required this.allowedDomains,
    required this.disclosure,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'enabled': enabled,
    'partnerId': partnerId,
    'secretConfigured': secretReference?.isNotEmpty == true,
    'allowedDomains': allowedDomains,
    'disclosure': disclosure,
  };
}

final class MarketplaceOffer {
  final String id;
  final String programId;
  final String title;
  final String seller;
  final String url;
  final int priceCents;
  final int shippingCents;
  final int? deliveryDays;
  final String currency;
  final bool active;
  final DateTime verifiedAt;

  const MarketplaceOffer({
    required this.id,
    required this.programId,
    required this.title,
    required this.seller,
    required this.url,
    required this.priceCents,
    required this.shippingCents,
    this.deliveryDays,
    required this.currency,
    required this.active,
    required this.verifiedAt,
  });

  int get totalCents => priceCents + shippingCents;

  Map<String, Object?> toJson() => {
    'id': id,
    'programId': programId,
    'title': title,
    'seller': seller,
    'priceCents': priceCents,
    'shippingCents': shippingCents,
    'totalCents': totalCents,
    'deliveryDays': deliveryDays,
    'currency': currency,
    'verifiedAt': verifiedAt.toIso8601String(),
  };
}

abstract interface class MarketplaceBackendStore {
  Future<List<AffiliateProgram>> listAffiliatePrograms();
  Future<void> saveAffiliateProgram(AffiliateProgram program);
  Future<void> saveMarketplaceOffer(MarketplaceOffer offer);
  Future<List<MarketplaceOffer>> searchMarketplaceOffers(String query);
  Future<MarketplaceOffer?> findMarketplaceOffer(String id);
  Future<String> recordAffiliateClick({
    required String id,
    required String businessId,
    required String userId,
    required MarketplaceOffer offer,
    required String destinationUrl,
  });
  Future<void> recordAffiliateConversion({
    required String id,
    required String programId,
    required String externalId,
    String? clickId,
    required int saleCents,
    required int commissionCents,
    required String status,
  });
  Future<Map<String, Object?>> affiliateMetrics();
}
