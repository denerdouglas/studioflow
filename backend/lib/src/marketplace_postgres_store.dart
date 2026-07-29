import 'dart:convert';

import 'package:postgres/postgres.dart';

import 'marketplace.dart';

final class MarketplacePostgresStore implements MarketplaceBackendStore {
  final Pool _pool;

  MarketplacePostgresStore.fromUrl(String databaseUrl)
    : _pool = Pool.withUrl(databaseUrl);

  AffiliateProgram _program(Map<String, dynamic> row) {
    final raw = row['allowed_domains'];
    final domains = raw is String ? jsonDecode(raw) as List : raw as List;
    return AffiliateProgram(
      id: row['id'] as String,
      name: row['name'] as String,
      enabled: row['enabled'] as bool,
      partnerId: row['partner_id'] as String?,
      secretReference: row['secret_reference'] as String?,
      allowedDomains: domains.cast<String>(),
      disclosure: row['disclosure'] as String,
    );
  }

  MarketplaceOffer _offer(Map<String, dynamic> row) => MarketplaceOffer(
    id: row['id'] as String,
    programId: row['program_id'] as String,
    title: row['title'] as String,
    seller: row['seller'] as String,
    url: row['destination_url'] as String,
    priceCents: row['price_cents'] as int,
    shippingCents: row['shipping_cents'] as int,
    deliveryDays: row['delivery_days'] as int?,
    currency: row['currency'] as String,
    active: row['active'] as bool,
    verifiedAt: row['verified_at'] as DateTime,
  );

  @override
  Future<List<AffiliateProgram>> listAffiliatePrograms() async {
    final result = await _pool.execute(
      'SELECT id, name, enabled, partner_id, secret_reference, '
      'allowed_domains, disclosure FROM affiliate_programs ORDER BY name',
    );
    return result.map((row) => _program(row.toColumnMap())).toList();
  }

  @override
  Future<void> saveAffiliateProgram(AffiliateProgram program) async {
    await _pool.execute(
      Sql.named('''
        INSERT INTO affiliate_programs
          (id, name, enabled, partner_id, secret_reference,
           allowed_domains, disclosure)
        VALUES (@id, @name, @enabled, @partnerId, @secretReference,
                CAST(@domains AS jsonb), @disclosure)
        ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name,
          enabled=EXCLUDED.enabled, partner_id=EXCLUDED.partner_id,
          secret_reference=EXCLUDED.secret_reference,
          allowed_domains=EXCLUDED.allowed_domains,
          disclosure=EXCLUDED.disclosure, updated_at=now()
      '''),
      parameters: {
        'id': program.id,
        'name': program.name,
        'enabled': program.enabled,
        'partnerId': program.partnerId,
        'secretReference': program.secretReference,
        'domains': jsonEncode(program.allowedDomains),
        'disclosure': program.disclosure,
      },
    );
  }

  @override
  Future<void> saveMarketplaceOffer(MarketplaceOffer offer) async {
    await _pool.execute(
      Sql.named('''
        INSERT INTO marketplace_offers
          (id, program_id, title, seller, destination_url, price_cents,
           shipping_cents, delivery_days, currency, active, verified_at)
        VALUES (@id, @programId, @title, @seller, @url, @price, @shipping,
                @days, @currency, @active, @verifiedAt)
        ON CONFLICT (id) DO UPDATE SET title=EXCLUDED.title,
          seller=EXCLUDED.seller, destination_url=EXCLUDED.destination_url,
          price_cents=EXCLUDED.price_cents,
          shipping_cents=EXCLUDED.shipping_cents,
          delivery_days=EXCLUDED.delivery_days, active=EXCLUDED.active,
          verified_at=EXCLUDED.verified_at, updated_at=now()
      '''),
      parameters: {
        'id': offer.id,
        'programId': offer.programId,
        'title': offer.title,
        'seller': offer.seller,
        'url': offer.url,
        'price': offer.priceCents,
        'shipping': offer.shippingCents,
        'days': offer.deliveryDays,
        'currency': offer.currency,
        'active': offer.active,
        'verifiedAt': offer.verifiedAt,
      },
    );
  }

  @override
  Future<List<MarketplaceOffer>> searchMarketplaceOffers(String query) async {
    final result = await _pool.execute(
      Sql.named('''
        SELECT o.* FROM marketplace_offers o
        JOIN affiliate_programs p ON p.id=o.program_id
        WHERE o.active=true AND p.enabled=true
          AND (lower(o.title) LIKE @query OR lower(o.seller) LIKE @query)
        ORDER BY (o.price_cents + o.shipping_cents),
                 o.delivery_days NULLS LAST
        LIMIT 100
      '''),
      parameters: {'query': '%${query.trim().toLowerCase()}%'},
    );
    return result.map((row) => _offer(row.toColumnMap())).toList();
  }

  @override
  Future<MarketplaceOffer?> findMarketplaceOffer(String id) async {
    final result = await _pool.execute(
      Sql.named('''
        SELECT o.* FROM marketplace_offers o
        JOIN affiliate_programs p ON p.id=o.program_id
        WHERE o.id=@id AND o.active=true AND p.enabled=true
      '''),
      parameters: {'id': id},
    );
    return result.isEmpty ? null : _offer(result.single.toColumnMap());
  }

  @override
  Future<String> recordAffiliateClick({
    required String id,
    required String businessId,
    required String userId,
    required MarketplaceOffer offer,
    required String destinationUrl,
  }) async {
    await _pool.runTx((tx) async {
      await tx.execute(
        Sql.named("SELECT set_config('app.business_id', @id, true)"),
        parameters: {'id': businessId},
      );
      await tx.execute(
        Sql.named('''
          INSERT INTO affiliate_clicks
            (id, business_id, user_id, offer_id, program_id, destination_url)
          VALUES (@id, @businessId, @userId, @offerId, @programId, @url)
        '''),
        parameters: {
          'id': id,
          'businessId': businessId,
          'userId': userId,
          'offerId': offer.id,
          'programId': offer.programId,
          'url': destinationUrl,
        },
      );
    });
    return id;
  }

  @override
  Future<void> recordAffiliateConversion({
    required String id,
    required String programId,
    required String externalId,
    String? clickId,
    required int saleCents,
    required int commissionCents,
    required String status,
  }) async {
    await _pool.execute(
      Sql.named('''
        INSERT INTO affiliate_conversions
          (id, program_id, external_id, click_id, sale_cents,
           commission_cents, status)
        VALUES (@id, @programId, @externalId, @clickId, @sale,
                @commission, @status)
        ON CONFLICT (program_id, external_id) DO UPDATE SET
          click_id=EXCLUDED.click_id, sale_cents=EXCLUDED.sale_cents,
          commission_cents=EXCLUDED.commission_cents,
          status=EXCLUDED.status, updated_at=now()
      '''),
      parameters: {
        'id': id,
        'programId': programId,
        'externalId': externalId,
        'clickId': clickId,
        'sale': saleCents,
        'commission': commissionCents,
        'status': status,
      },
    );
  }

  @override
  Future<Map<String, Object?>> affiliateMetrics() async {
    final result = await _pool.execute('''
      SELECT (SELECT count(*) FROM affiliate_clicks) AS clicks,
        count(*) AS conversions,
        coalesce(sum(commission_cents)
          FILTER (WHERE status='estimada'),0) AS estimated,
        coalesce(sum(commission_cents)
          FILTER (WHERE status='confirmada'),0) AS confirmed,
        coalesce(sum(commission_cents)
          FILTER (WHERE status='cancelada'),0) AS cancelled
      FROM affiliate_conversions
    ''');
    final row = result.single.toColumnMap();
    return {
      'clicks': row['clicks'],
      'conversions': row['conversions'],
      'commissionEstimatedCents': row['estimated'],
      'commissionConfirmedCents': row['confirmed'],
      'commissionCancelledCents': row['cancelled'],
    };
  }

  Future<void> close() => _pool.close();
}
