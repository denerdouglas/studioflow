import 'package:postgres/postgres.dart';

import 'commercial_campaigns.dart';

final class CommercialCampaignPostgresStore implements CommercialCampaignStore {
  final Pool pool;

  CommercialCampaignPostgresStore(this.pool);

  CommercialCampaign _read(ResultRow row) => CommercialCampaign(
    id: row[0] as String,
    title: row[1] as String,
    subtitle: row[2] as String?,
    description: row[3] as String,
    imageUrl: row[4] as String?,
    destinationUrl: row[5] as String,
    category: row[6] as String,
    sourceType: row[7] as String,
    priceCents: row[8] as int?,
    originalPriceCents: row[9] as int?,
    badge: row[10] as String?,
    ctaText: row[11] as String,
    priority: row[12] as int,
    active: row[13] as bool,
    segments: (row[14] as List?)?.cast<String>() ?? const [],
    startsAt: row[15] as DateTime?,
    endsAt: row[16] as DateTime?,
    createdAt: row[17] as DateTime,
    updatedAt: row[18] as DateTime,
    globalProductId: row[19] as String?,
    courseId: row[20] as String?,
  );

  static const _columns = '''id, title, subtitle, description, image_url,
    destination_url, category, source_type, price_cents, original_price_cents,
    badge, cta_text, priority, active, segments, starts_at, ends_at,
    created_at, updated_at, global_product_id, course_id''';

  @override
  Future<List<CommercialCampaign>> listCampaigns() async => (await pool.execute(
    'SELECT $_columns FROM commercial_campaigns',
  )).map(_read).toList();

  @override
  Future<CommercialCampaign?> findCampaign(String id) async {
    final rows = await pool.execute(
      Sql.named('SELECT $_columns FROM commercial_campaigns WHERE id = @id'),
      parameters: {'id': id},
    );
    return rows.isEmpty ? null : _read(rows.first);
  }

  @override
  Future<void> saveCampaign(CommercialCampaign item) async {
    await pool.execute(
      Sql.named('''
        INSERT INTO commercial_campaigns ($_columns)
        VALUES (@id, @title, @subtitle, @description, @imageUrl,
          @destinationUrl, @category, @sourceType, @price, @originalPrice,
          @badge, @ctaText, @priority, @active, @segments, @startsAt, @endsAt,
          @createdAt, @updatedAt, @globalProductId, @courseId)
        ON CONFLICT (id) DO UPDATE SET title = EXCLUDED.title,
          subtitle = EXCLUDED.subtitle, description = EXCLUDED.description,
          image_url = EXCLUDED.image_url,
          destination_url = EXCLUDED.destination_url,
          category = EXCLUDED.category, source_type = EXCLUDED.source_type,
          price_cents = EXCLUDED.price_cents,
          original_price_cents = EXCLUDED.original_price_cents,
          badge = EXCLUDED.badge, cta_text = EXCLUDED.cta_text,
          priority = EXCLUDED.priority, active = EXCLUDED.active,
          segments = EXCLUDED.segments, starts_at = EXCLUDED.starts_at,
          ends_at = EXCLUDED.ends_at, updated_at = EXCLUDED.updated_at,
          global_product_id = EXCLUDED.global_product_id,
          course_id = EXCLUDED.course_id
      '''),
      parameters: {
        'id': item.id,
        'title': item.title,
        'subtitle': item.subtitle,
        'description': item.description,
        'imageUrl': item.imageUrl,
        'destinationUrl': item.destinationUrl,
        'category': item.category,
        'sourceType': item.sourceType,
        'price': item.priceCents,
        'originalPrice': item.originalPriceCents,
        'badge': item.badge,
        'ctaText': item.ctaText,
        'priority': item.priority,
        'active': item.active,
        'segments': item.segments,
        'startsAt': item.startsAt,
        'endsAt': item.endsAt,
        'createdAt': item.createdAt,
        'updatedAt': item.updatedAt,
        'globalProductId': item.globalProductId,
        'courseId': item.courseId,
      },
    );
  }

  @override
  Future<void> recordCampaignEvent({
    required String id,
    required String campaignId,
    required String businessId,
    required String userId,
    required String type,
    required DateTime occurredAt,
  }) async {
    await pool.execute(
      Sql.named('''INSERT INTO commercial_campaign_events
        (id, campaign_id, business_id, user_id, event_type, occurred_at)
        VALUES (@id, @campaignId, @businessId, @userId, @type, @occurredAt)'''),
      parameters: {
        'id': id,
        'campaignId': campaignId,
        'businessId': businessId,
        'userId': userId,
        'type': type,
        'occurredAt': occurredAt,
      },
    );
  }

  @override
  Future<List<Map<String, Object?>>> campaignMetrics() async {
    final rows = await pool.execute('''SELECT c.id,
      COUNT(e.id) FILTER (WHERE e.event_type='impression') AS impressions,
      COUNT(e.id) FILTER (WHERE e.event_type='click') AS clicks
      FROM commercial_campaigns c
      LEFT JOIN commercial_campaign_events e ON e.campaign_id=c.id
      GROUP BY c.id ORDER BY c.id''');
    return rows.map((row) {
      final impressions = row[1] as int;
      final clicks = row[2] as int;
      return <String, Object?>{
        'campaignId': row[0] as String,
        'impressions': impressions,
        'clicks': clicks,
        'ctr': impressions == 0 ? 0 : clicks / impressions,
      };
    }).toList();
  }
}
