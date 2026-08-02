import 'package:postgres/postgres.dart';
import 'package:studioflow_backend/src/postgres_store.dart';
import 'academy.dart';

final class AcademyPostgresStore implements AcademyBackendStore {
  final Pool _pool;

  AcademyPostgresStore(PostgresBackendStore backendStore) : _pool = backendStore.pool;
  
  AcademyPostgresStore.fromPool(this._pool);

  @override
  Future<List<AcademyCategory>> getCategories() async {
    final result = await _pool.execute('''
      SELECT id, name, display_order, created_at
      FROM academy_categories
      ORDER BY display_order ASC, name ASC
    ''');
    return result.map((r) => AcademyCategory(
      id: r[0] as String,
      name: r[1] as String,
      displayOrder: r[2] as int,
      createdAt: r[3] as DateTime,
    )).toList();
  }
  
  @override
  Future<List<AcademyCourse>> searchCourses({
    String? query,
    String? categoryId,
    int limit = 20,
    int offset = 0,
  }) async {
    final conditions = <String>["publication_status IN ('published', 'coming_soon')"];
    final parameters = <String, Object?>{
      'limit': limit,
      'offset': offset,
    };

    if (query != null && query.trim().isNotEmpty) {
      conditions.add("title ILIKE @query");
      parameters['query'] = '%${query.trim()}%';
    }

    if (categoryId != null && categoryId.isNotEmpty) {
      conditions.add("category_id = @categoryId");
      parameters['categoryId'] = categoryId;
    }

    final whereClause = conditions.join(' AND ');

    final result = await _pool.execute(
      Sql.named('''
        SELECT id, external_id, title, short_description, instructor, image_url,
               price_cents, currency, partner_id, category_id, source_type,
               publication_status, rating, reviews_count, redirect_url
        FROM academy_courses
        WHERE $whereClause
        ORDER BY created_at DESC
        LIMIT @limit OFFSET @offset
      '''),
      parameters: parameters,
    );

    return result.map((r) => AcademyCourse(
      id: r[0] as String,
      externalId: r[1] as String?,
      title: r[2] as String,
      shortDescription: r[3] as String?,
      instructor: r[4] as String?,
      imageUrl: r[5] as String?,
      priceCents: r[6] as int?,
      currency: r[7] as String?,
      partnerId: r[8] as String,
      categoryId: r[9] as String,
      sourceType: r[10] as String,
      publicationStatus: r[11] as String,
      rating: r[12] is num ? (r[12] as num).toDouble() : (r[12] is String ? double.parse(r[12] as String) : null),
      reviewsCount: r[13] as int?,
      redirectUrl: r[14] as String?,
    )).toList();
  }
  
  @override
  Future<int> countCourses({String? query, String? categoryId}) async {
    final conditions = <String>["publication_status IN ('published', 'coming_soon')"];
    final parameters = <String, Object?>{};

    if (query != null && query.trim().isNotEmpty) {
      conditions.add("title ILIKE @query");
      parameters['query'] = '%${query.trim()}%';
    }

    if (categoryId != null && categoryId.isNotEmpty) {
      conditions.add("category_id = @categoryId");
      parameters['categoryId'] = categoryId;
    }

    final whereClause = conditions.join(' AND ');

    final result = await _pool.execute(
      Sql.named('''
        SELECT COUNT(*)
        FROM academy_courses
        WHERE $whereClause
      '''),
      parameters: parameters,
    );

    return (result.first[0] as int?) ?? 0;
  }
  
  @override
  Future<void> logSearch({
    required String query,
    String? categoryId,
    required int resultsCount,
    String? businessId,
    String? userId,
  }) async {
    await _pool.execute(
      Sql.named('''
        INSERT INTO academy_search_logs (id, query, category_id, results_count, business_id, user_id, created_at)
        VALUES (gen_random_uuid(), @query, @categoryId, @resultsCount, @businessId, @userId, NOW())
      '''),
      parameters: {
        'query': query,
        'categoryId': categoryId,
        'resultsCount': resultsCount,
        'businessId': businessId,
        'userId': userId,
      },
    );
  }

  @override
  Future<void> createClick(AcademyClick click) async {
    await _pool.execute(
      Sql.named('''
        INSERT INTO academy_clicks (
          click_id, course_id, partner_id, campaign_id, destination_url,
          status, origin, business_id, user_id, created_at, expires_at
        ) VALUES (
          @clickId, @courseId, @partnerId, @campaignId, @destinationUrl,
          @status, @origin, @businessId, @userId, @createdAt, @expiresAt
        )
      '''),
      parameters: {
        'clickId': click.clickId,
        'courseId': click.courseId,
        'partnerId': click.partnerId,
        'campaignId': click.campaignId,
        'destinationUrl': click.destinationUrl,
        'status': click.status,
        'origin': click.origin,
        'businessId': click.businessId,
        'userId': click.userId,
        'createdAt': click.createdAt,
        'expiresAt': click.expiresAt,
      },
    );
  }
  
  @override
  Future<AcademyClick?> getClick(String clickId) async {
    final result = await _pool.execute(
      Sql.named('''
        SELECT click_id, course_id, partner_id, campaign_id, destination_url,
               status, failure_reason, origin, business_id, user_id,
               created_at, expires_at, redirected_at
        FROM academy_clicks
        WHERE click_id = @clickId
      '''),
      parameters: {'clickId': clickId},
    );
    if (result.isEmpty) return null;
    final r = result.first;
    return AcademyClick(
      clickId: r[0] as String,
      courseId: r[1] as String,
      partnerId: r[2] as String,
      campaignId: r[3] as String?,
      destinationUrl: r[4] as String,
      status: r[5] as String,
      failureReason: r[6] as String?,
      origin: r[7] as String?,
      businessId: r[8] as String?,
      userId: r[9] as String?,
      createdAt: r[10] as DateTime,
      expiresAt: r[11] as DateTime,
      redirectedAt: r[12] as DateTime?,
    );
  }
  
  @override
  Future<void> updateClickStatus(String clickId, String status, {String? failureReason, DateTime? redirectedAt}) async {
    await _pool.execute(
      Sql.named('''
        UPDATE academy_clicks
        SET status = @status,
            failure_reason = @failureReason,
            redirected_at = @redirectedAt
        WHERE click_id = @clickId
      '''),
      parameters: {
        'status': status,
        'failureReason': failureReason,
        'redirectedAt': redirectedAt,
        'clickId': clickId,
      },
    );
  }
  
  @override
  Future<AcademyCourse?> getCourseById(String id) async {
    final result = await _pool.execute(
      Sql.named('''
        SELECT id, external_id, title, short_description, instructor, image_url,
               price_cents, currency, partner_id, category_id, source_type,
               publication_status, rating, reviews_count, redirect_url
        FROM academy_courses
        WHERE id = @id
      '''),
      parameters: {'id': id},
    );
    if (result.isEmpty) return null;
    final r = result.first;
    return AcademyCourse(
      id: r[0] as String,
      externalId: r[1] as String?,
      title: r[2] as String,
      shortDescription: r[3] as String?,
      instructor: r[4] as String?,
      imageUrl: r[5] as String?,
      priceCents: r[6] as int?,
      currency: r[7] as String?,
      partnerId: r[8] as String,
      categoryId: r[9] as String,
      sourceType: r[10] as String,
      publicationStatus: r[11] as String,
      rating: r[12] is num ? (r[12] as num).toDouble() : (r[12] is String ? double.parse(r[12] as String) : null),
      reviewsCount: r[13] as int?,
      redirectUrl: r[14] as String?,
    );
  }
  
  @override
  Future<String?> getPartnerSlug(String partnerId) async {
    final result = await _pool.execute(
      Sql.named('SELECT slug FROM academy_partners WHERE id = @id'),
      parameters: {'id': partnerId},
    );
    if (result.isEmpty) return null;
    return result.first[0] as String;
  }
  
  @override
  Future<String?> getCategoryName(String categoryId) async {
    final result = await _pool.execute(
      Sql.named('SELECT name FROM academy_categories WHERE id = @id'),
      parameters: {'id': categoryId},
    );
    if (result.isEmpty) return null;
    return result.first[0] as String;
  }
  
  @override
  Future<bool> isPartnerActive(String partnerId) async {
    final result = await _pool.execute(
      Sql.named("SELECT status FROM academy_partners WHERE id = @id AND status = 'active'"),
      parameters: {'id': partnerId},
    );
    return result.isNotEmpty;
  }
  
  @override
  Future<bool> isCampaignActive(String? campaignId) async {
    if (campaignId == null) return false;
    final result = await _pool.execute(
      Sql.named("SELECT status FROM academy_campaigns WHERE id = @id AND status = 'active' AND (expires_at IS NULL OR expires_at > NOW())"),
      parameters: {'id': campaignId},
    );
    return result.isNotEmpty;
  }
}
