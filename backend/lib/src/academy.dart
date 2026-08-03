import 'package:uuid/uuid.dart';
import 'models.dart';

final class AcademyCategory {
  final String id;
  final String name;
  final int displayOrder;
  final DateTime createdAt;

  const AcademyCategory({
    required this.id,
    required this.name,
    required this.displayOrder,
    required this.createdAt,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'displayOrder': displayOrder,
  };
}

final class AcademyCourse {
  final String id;
  final String? externalId;
  final String title;
  final String? shortDescription;
  final String? instructor;
  final String? imageUrl;
  final int? priceCents;
  final String? currency;
  final String partnerId;
  final String categoryId;
  final String sourceType; // 'partner', 'studioflow'
  final String
  publicationStatus; // 'draft', 'coming_soon', 'published', 'suspended', 'archived'
  final double? rating;
  final int? reviewsCount;
  final String? redirectUrl;
  final List<String>? badges;

  const AcademyCourse({
    required this.id,
    this.externalId,
    required this.title,
    this.shortDescription,
    this.instructor,
    this.imageUrl,
    this.priceCents,
    this.currency,
    required this.partnerId,
    required this.categoryId,
    required this.sourceType,
    required this.publicationStatus,
    this.rating,
    this.reviewsCount,
    this.redirectUrl,
    this.badges,
  });

  Map<String, Object?> toPublicJson({String? clickId}) {
    return {
      'id': id,
      if (externalId != null) 'externalId': externalId,
      'title': title,
      if (shortDescription != null) 'shortDescription': shortDescription,
      if (instructor != null) 'instructor': instructor,
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (priceCents != null) 'price': priceCents,
      if (currency != null) 'currency': currency,
      'sourceType': sourceType,
      'publicationStatus': publicationStatus,
      if (rating != null) 'rating': rating,
      if (reviewsCount != null) 'reviewsCount': reviewsCount,
      // ignore: use_null_aware_elements
      if (clickId != null) 'clickId': clickId,
      if (badges != null && badges!.isNotEmpty) 'badges': badges,
    };
  }
}

final class AcademyClick {
  final String clickId;
  final String courseId;
  final String partnerId;
  final String? campaignId;
  final String destinationUrl;
  final String
  status; // 'created', 'redirected', 'expired', 'blocked', 'failed'
  final String? failureReason;
  final String? origin;
  final String? businessId;
  final String? userId;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? redirectedAt;

  const AcademyClick({
    required this.clickId,
    required this.courseId,
    required this.partnerId,
    this.campaignId,
    required this.destinationUrl,
    required this.status,
    this.failureReason,
    this.origin,
    this.businessId,
    this.userId,
    required this.createdAt,
    required this.expiresAt,
    this.redirectedAt,
  });
}

abstract class AcademyBackendStore {
  Future<List<AcademyCategory>> getCategories();

  Future<List<AcademyCourse>> searchCourses({
    String? query,
    String? categoryId,
    int limit = 20,
    int offset = 0,
  });

  Future<int> countCourses({String? query, String? categoryId});

  Future<void> logSearch({
    required String query,
    String? categoryId,
    required int resultsCount,
    String? businessId,
    String? userId,
  });

  Future<void> createClick(AcademyClick click);
  Future<AcademyClick?> getClick(String clickId);
  Future<void> updateClickStatus(
    String clickId,
    String status, {
    String? failureReason,
    DateTime? redirectedAt,
  });

  Future<AcademyCourse?> getCourseById(String id);
  Future<String?> getPartnerSlug(String partnerId);
  Future<String?> getCategoryName(String categoryId);
  Future<bool> isPartnerActive(String partnerId);
  Future<bool> isCampaignActive(String? campaignId);
}

class AcademyService {
  final AcademyBackendStore store;
  final Uuid _uuid;

  AcademyService(this.store, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  Future<Map<String, dynamic>> search(
    AuthContext auth,
    String? query,
    String? categoryId,
    int page,
    int pageSize,
  ) async {
    final effectivePageSize = pageSize.clamp(1, 100);
    final offset = (page - 1) * effectivePageSize;

    final courses = await store.searchCourses(
      query: query,
      categoryId: categoryId,
      limit: effectivePageSize,
      offset: offset,
    );

    final total = await store.countCourses(
      query: query,
      categoryId: categoryId,
    );

    await store.logSearch(
      query: query ?? '',
      categoryId: categoryId,
      resultsCount: total,
      businessId: auth.businessId,
      userId: auth.userId,
    );

    final results = <Map<String, dynamic>>[];
    for (final course in courses) {
      String? clickId;
      if (course.publicationStatus == 'published' &&
          course.redirectUrl != null) {
        final partnerActive = await store.isPartnerActive(course.partnerId);
        if (partnerActive) {
          clickId = 'ac_${_uuid.v4().replaceAll('-', '')}';
          final click = AcademyClick(
            clickId: clickId,
            courseId: course.id,
            partnerId: course.partnerId,
            destinationUrl: course.redirectUrl!,
            status: 'created',
            origin: 'academy_search',
            businessId: auth.businessId,
            userId: auth.userId,
            createdAt: DateTime.now().toUtc(),
            expiresAt: DateTime.now().toUtc().add(const Duration(hours: 24)),
          );
          await store.createClick(click);
        }
      }

      final json = course.toPublicJson(clickId: clickId);
      json['platform'] =
          await store.getPartnerSlug(course.partnerId) ?? 'unknown';
      json['category'] =
          await store.getCategoryName(course.categoryId) ?? 'unknown';
      results.add(json);
    }

    return {
      'query': query,
      'category': categoryId,
      'page': page,
      'pageSize': effectivePageSize,
      'total': total,
      'fetchedAt': DateTime.now().toUtc().toIso8601String(),
      'courses': results,
    };
  }
}

class SecureRedirectService {
  final AcademyBackendStore store;

  SecureRedirectService(this.store);

  Future<String> processRedirect(String clickId) async {
    final click = await store.getClick(clickId);
    if (click == null) {
      throw RedirectException('Click ID não encontrado');
    }

    if (click.status != 'created') {
      await store.updateClickStatus(
        clickId,
        'blocked',
        failureReason: 'Click already used or blocked',
      );
      throw RedirectException('Link inválido ou já utilizado');
    }

    if (click.expiresAt.isBefore(DateTime.now().toUtc())) {
      await store.updateClickStatus(
        clickId,
        'expired',
        failureReason: 'Click expired',
      );
      throw RedirectException('O link expirou');
    }

    final course = await store.getCourseById(click.courseId);
    if (course == null || course.publicationStatus != 'published') {
      await store.updateClickStatus(
        clickId,
        'blocked',
        failureReason: 'Course not published or not found',
      );
      throw RedirectException('Curso indisponível');
    }

    final partnerActive = await store.isPartnerActive(click.partnerId);
    if (!partnerActive) {
      await store.updateClickStatus(
        clickId,
        'blocked',
        failureReason: 'Partner inactive',
      );
      throw RedirectException('Parceiro inativo');
    }

    if (click.campaignId != null) {
      final campaignActive = await store.isCampaignActive(click.campaignId);
      if (!campaignActive) {
        await store.updateClickStatus(
          clickId,
          'blocked',
          failureReason: 'Campaign inactive',
        );
        throw RedirectException('Campanha inativa');
      }
    }

    final dest = Uri.tryParse(click.destinationUrl);
    if (dest == null || !dest.hasScheme || dest.scheme != 'https') {
      await store.updateClickStatus(
        clickId,
        'blocked',
        failureReason: 'Invalid destination URL (not HTTPS)',
      );
      throw RedirectException('Destino inválido');
    }

    if (['localhost', '127.0.0.1', '::1'].contains(dest.host)) {
      await store.updateClickStatus(
        clickId,
        'blocked',
        failureReason: 'Localhost blocked',
      );
      throw RedirectException('Destino inválido');
    }

    // IP blocking rules can be extended here
    // For now, block some basic ones, or leave it to standard DNS checks

    if (dest.userInfo.isNotEmpty) {
      await store.updateClickStatus(
        clickId,
        'blocked',
        failureReason: 'Credentials in URL blocked',
      );
      throw RedirectException('Destino inválido');
    }

    await store.updateClickStatus(
      clickId,
      'redirected',
      redirectedAt: DateTime.now().toUtc(),
    );
    return click.destinationUrl;
  }
}

class RedirectException implements Exception {
  final String message;
  RedirectException(this.message);
  @override
  String toString() => message;
}
