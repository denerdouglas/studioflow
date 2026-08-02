class MarketplaceSearchResult {
  final List<MarketplaceProductGroup> results;
  final String? message;
  final int page;
  final int total;
  final DateTime fetchedAt;

  MarketplaceSearchResult({
    required this.results,
    this.message,
    required this.page,
    required this.total,
    required this.fetchedAt,
  });

  factory MarketplaceSearchResult.fromJson(Map<String, dynamic> json) {
    return MarketplaceSearchResult(
      results: (json['results'] as List?)
              ?.map((e) => MarketplaceProductGroup.fromJson(e))
              .toList() ??
          [],
      message: json['message'] as String?,
      page: json['page'] as int? ?? 1,
      total: json['total'] as int? ?? 0,
      fetchedAt: json['fetched_at'] != null
          ? DateTime.parse(json['fetched_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'results': results.map((e) => e.toJson()).toList(),
      'message': message,
      'page': page,
      'total': total,
      'fetched_at': fetchedAt.toIso8601String(),
    };
  }
}

class MarketplaceProductGroup {
  final String? externalProductGroupId;
  final String? gtin;
  final String? normalizedProductId;
  final String title;
  final String? imageUrl;
  final List<MarketplaceOffer> offers;

  MarketplaceProductGroup({
    this.externalProductGroupId,
    this.gtin,
    this.normalizedProductId,
    required this.title,
    this.imageUrl,
    required this.offers,
  });

  factory MarketplaceProductGroup.fromJson(Map<String, dynamic> json) {
    return MarketplaceProductGroup(
      externalProductGroupId: json['external_product_group_id'] as String?,
      gtin: json['gtin'] as String?,
      normalizedProductId: json['normalized_product_id'] as String?,
      title: json['title'] as String? ?? 'Produto Desconhecido',
      imageUrl: json['image_url'] as String?,
      offers: (json['offers'] as List?)
              ?.map((e) => MarketplaceOffer.fromJson(e))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'external_product_group_id': externalProductGroupId,
      'gtin': gtin,
      'normalized_product_id': normalizedProductId,
      'title': title,
      'image_url': imageUrl,
      'offers': offers.map((e) => e.toJson()).toList(),
    };
  }
}

class MarketplaceOffer {
  final MarketplacePartner partner;
  final String clickId;
  final String? externalProductId;
  final int priceCents;
  final int? shippingCents;
  final int? deliveryDays;
  final double? rating;
  final String? coupon;
  final DateTime updatedAt;
  final List<String> badges;

  MarketplaceOffer({
    required this.partner,
    required this.clickId,
    this.externalProductId,
    required this.priceCents,
    this.shippingCents,
    this.deliveryDays,
    this.rating,
    this.coupon,
    required this.updatedAt,
    this.badges = const [],
  });

  factory MarketplaceOffer.fromJson(Map<String, dynamic> json) {
    return MarketplaceOffer(
      partner: MarketplacePartner.fromJson(json['partner'] ?? {}),
      clickId: json['click_id'] as String? ?? '',
      externalProductId: json['external_product_id'] as String?,
      priceCents: json['price_cents'] as int? ?? 0,
      shippingCents: json['shipping_cents'] as int?,
      deliveryDays: json['delivery_days'] as int?,
      rating: (json['rating'] as num?)?.toDouble(),
      coupon: json['coupon'] as String?,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
      badges: (json['badges'] as List?)?.map((e) => e.toString()).toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'partner': partner.toJson(),
      'click_id': clickId,
      'external_product_id': externalProductId,
      'price_cents': priceCents,
      'shipping_cents': shippingCents,
      'delivery_days': deliveryDays,
      'rating': rating,
      'coupon': coupon,
      'updated_at': updatedAt.toIso8601String(),
      'badges': badges,
    };
  }
}

class MarketplacePartner {
  final String slug;
  final String name;

  MarketplacePartner({
    required this.slug,
    required this.name,
  });

  factory MarketplacePartner.fromJson(Map<String, dynamic> json) {
    return MarketplacePartner(
      slug: json['slug'] as String? ?? 'unknown',
      name: json['name'] as String? ?? 'Desconhecido',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'slug': slug,
      'name': name,
    };
  }
}
