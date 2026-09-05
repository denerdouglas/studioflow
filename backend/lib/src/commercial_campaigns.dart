import 'package:uuid/uuid.dart';

import 'models.dart';

const campaignSourceTypes = {
  'rolg_academy',
  'affiliate',
  'partner',
  'internal',
};

final class CommercialCampaign {
  final String id;
  final String title;
  final String? subtitle;
  final String description;
  final String? imageUrl;
  final String destinationUrl;
  final String category;
  final String sourceType;
  final int? priceCents;
  final int? originalPriceCents;
  final String? badge;
  final String ctaText;
  final int priority;
  final bool active;
  final List<String> segments;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? globalProductId;
  final String? courseId;

  const CommercialCampaign({
    required this.id,
    required this.title,
    this.subtitle,
    required this.description,
    this.imageUrl,
    required this.destinationUrl,
    required this.category,
    required this.sourceType,
    this.priceCents,
    this.originalPriceCents,
    this.badge,
    required this.ctaText,
    required this.priority,
    required this.active,
    this.segments = const [],
    this.startsAt,
    this.endsAt,
    required this.createdAt,
    required this.updatedAt,
    this.globalProductId,
    this.courseId,
  });

  bool isAvailableAt(DateTime now) =>
      active &&
      (startsAt == null || !startsAt!.isAfter(now)) &&
      (endsAt == null || endsAt!.isAfter(now));

  bool targets(String? segment) {
    if (segments.isEmpty) return true;
    final normalized = segment?.trim().toLowerCase();
    return normalized != null && segments.contains(normalized);
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'description': description,
    'imageUrl': imageUrl,
    'destinationUrl': destinationUrl,
    'category': category,
    'sourceType': sourceType,
    'price': priceCents,
    'originalPrice': originalPriceCents,
    'badge': badge,
    'ctaText': ctaText,
    'priority': priority,
    'active': active,
    'segments': segments,
    'startsAt': startsAt?.toIso8601String(),
    'endsAt': endsAt?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'globalProductId': globalProductId,
    'courseId': courseId,
  };
}

abstract interface class CommercialCampaignStore {
  Future<List<CommercialCampaign>> listCampaigns();
  Future<CommercialCampaign?> findCampaign(String id);
  Future<void> saveCampaign(CommercialCampaign campaign);
  Future<void> recordCampaignEvent({
    required String id,
    required String campaignId,
    required String businessId,
    required String userId,
    required String type,
    required DateTime occurredAt,
  });
  Future<List<Map<String, Object?>>> campaignMetrics();
}

final class CommercialCampaignService {
  final CommercialCampaignStore store;
  final Uuid _uuid;
  final DateTime Function() _now;

  CommercialCampaignService(this.store, {Uuid? uuid, DateTime Function()? now})
    : _uuid = uuid ?? const Uuid(),
      _now = now ?? (() => DateTime.now().toUtc());

  static bool isSafeHttps(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !{'localhost', '127.0.0.1', '::1'}.contains(uri.host.toLowerCase());
  }

  Future<List<CommercialCampaign>> available({String? segment}) async {
    final now = _now();
    final campaigns =
        (await store.listCampaigns())
            .where((item) => item.isAvailableAt(now) && item.targets(segment))
            .toList()
          ..sort((a, b) {
            final priority = b.priority.compareTo(a.priority);
            return priority != 0
                ? priority
                : b.updatedAt.compareTo(a.updatedAt);
          });
    return campaigns;
  }

  Future<CommercialCampaign?> detail(String id, {String? segment}) async {
    final item = await store.findCampaign(id);
    if (item == null || !item.isAvailableAt(_now()) || !item.targets(segment)) {
      return null;
    }
    return item;
  }

  Future<void> event(AuthContext actor, String campaignId, String type) async {
    if (actor.businessId == null || !{'impression', 'click'}.contains(type)) {
      throw ArgumentError('Evento inválido.');
    }
    final campaign = await store.findCampaign(campaignId);
    if (campaign == null || !campaign.isAvailableAt(_now())) {
      throw StateError('Campanha indisponível.');
    }
    await store.recordCampaignEvent(
      id: _uuid.v4(),
      campaignId: campaignId,
      businessId: actor.businessId!,
      userId: actor.userId,
      type: type,
      occurredAt: _now(),
    );
  }
}
