import 'academy.dart';

class AcademyMemoryStore implements AcademyBackendStore {
  final List<AcademyCategory> _academyCategories = [];
  final List<AcademyCourse> _academyCourses = [];
  final Map<String, AcademyClick> _academyClicks = {};
  final List<Map<String, dynamic>> _academySearchLogs = [];
  final Map<String, String> _academyPartners = {};
  final Map<String, bool> _academyPartnerActive = {};
  final Map<String, bool> _academyCampaignActive = {};

  void seedAcademy(
    List<AcademyCategory> categories,
    List<AcademyCourse> courses,
    Map<String, String> partners,
    Map<String, bool> partnerActive,
    Map<String, bool> campaignActive,
  ) {
    _academyCategories.clear();
    _academyCategories.addAll(categories);
    _academyCourses.clear();
    _academyCourses.addAll(courses);
    _academyPartners.clear();
    _academyPartners.addAll(partners);
    _academyPartnerActive.clear();
    _academyPartnerActive.addAll(partnerActive);
    _academyCampaignActive.clear();
    _academyCampaignActive.addAll(campaignActive);
  }

  @override
  Future<List<AcademyCategory>> getCategories() async => _academyCategories;

  @override
  Future<List<AcademyCourse>> searchCourses({
    String? query,
    String? categoryId,
    int limit = 20,
    int offset = 0,
  }) async {
    return _academyCourses
        .where((c) {
          if (c.publicationStatus != 'published' &&
              c.publicationStatus != 'coming_soon') {
            return false;
          }
          if (categoryId != null &&
              categoryId.isNotEmpty &&
              c.categoryId != categoryId) {
            return false;
          }
          if (query != null &&
              query.trim().isNotEmpty &&
              !c.title.toLowerCase().contains(query.trim().toLowerCase())) {
            return false;
          }
          return true;
        })
        .skip(offset)
        .take(limit)
        .toList();
  }

  @override
  Future<int> countCourses({String? query, String? categoryId}) async {
    return _academyCourses.where((c) {
      if (c.publicationStatus != 'published' &&
          c.publicationStatus != 'coming_soon') {
        return false;
      }
      if (categoryId != null &&
          categoryId.isNotEmpty &&
          c.categoryId != categoryId) {
        return false;
      }
      if (query != null &&
          query.trim().isNotEmpty &&
          !c.title.toLowerCase().contains(query.trim().toLowerCase())) {
        return false;
      }
      return true;
    }).length;
  }

  @override
  Future<void> logSearch({
    required String query,
    String? categoryId,
    required int resultsCount,
    String? businessId,
    String? userId,
  }) async {
    _academySearchLogs.add({
      'query': query,
      'categoryId': categoryId,
      'resultsCount': resultsCount,
      'businessId': businessId,
      'userId': userId,
    });
  }

  @override
  Future<void> createClick(AcademyClick click) async {
    _academyClicks[click.clickId] = click;
  }

  @override
  Future<AcademyClick?> getClick(String clickId) async {
    return _academyClicks[clickId];
  }

  @override
  Future<void> updateClickStatus(
    String clickId,
    String status, {
    String? failureReason,
    DateTime? redirectedAt,
  }) async {
    final click = _academyClicks[clickId];
    if (click != null) {
      _academyClicks[clickId] = AcademyClick(
        clickId: click.clickId,
        courseId: click.courseId,
        partnerId: click.partnerId,
        campaignId: click.campaignId,
        destinationUrl: click.destinationUrl,
        status: status,
        failureReason: failureReason,
        origin: click.origin,
        businessId: click.businessId,
        userId: click.userId,
        createdAt: click.createdAt,
        expiresAt: click.expiresAt,
        redirectedAt: redirectedAt,
      );
    }
  }

  @override
  Future<AcademyCourse?> getCourseById(String id) async {
    try {
      return _academyCourses.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> getPartnerSlug(String partnerId) async {
    return _academyPartners[partnerId];
  }

  @override
  Future<String?> getCategoryName(String categoryId) async {
    try {
      return _academyCategories.firstWhere((c) => c.id == categoryId).name;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> isPartnerActive(String partnerId) async {
    return _academyPartnerActive[partnerId] ?? false;
  }

  @override
  Future<bool> isCampaignActive(String? campaignId) async {
    if (campaignId == null) return false;
    return _academyCampaignActive[campaignId] ?? false;
  }
}
