import 'commercial_campaigns.dart';

final class CommercialCampaignMemoryStore implements CommercialCampaignStore {
  final Map<String, CommercialCampaign> campaigns = {};
  final List<Map<String, Object?>> events = [];

  void seed(Iterable<CommercialCampaign> values) {
    campaigns.addEntries(values.map((item) => MapEntry(item.id, item)));
  }

  @override
  Future<CommercialCampaign?> findCampaign(String id) async => campaigns[id];

  @override
  Future<List<CommercialCampaign>> listCampaigns() async =>
      campaigns.values.toList();

  @override
  Future<void> saveCampaign(CommercialCampaign campaign) async {
    campaigns[campaign.id] = campaign;
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
    events.add({
      'id': id,
      'campaignId': campaignId,
      'businessId': businessId,
      'userId': userId,
      'type': type,
      'occurredAt': occurredAt,
    });
  }

  @override
  Future<List<Map<String, Object?>>> campaignMetrics() async {
    return campaigns.values.map((campaign) {
      final impressions = events
          .where(
            (e) => e['campaignId'] == campaign.id && e['type'] == 'impression',
          )
          .length;
      final clicks = events
          .where((e) => e['campaignId'] == campaign.id && e['type'] == 'click')
          .length;
      return <String, Object?>{
        'campaignId': campaign.id,
        'impressions': impressions,
        'clicks': clicks,
        'ctr': impressions == 0 ? 0 : clicks / impressions,
      };
    }).toList();
  }
}
