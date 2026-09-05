import 'commercial_campaign.dart';

final class GlobalCourse {
  final String id;
  final String title;
  final String provider;
  final String description;
  final String? imageUrl;
  final String category;
  final List<String> keywords;
  final CommercialCampaign? campaign;

  const GlobalCourse({
    required this.id,
    required this.title,
    required this.provider,
    required this.description,
    this.imageUrl,
    required this.category,
    this.keywords = const [],
    this.campaign,
  });

  factory GlobalCourse.fromJson(Map<String, dynamic> json) => GlobalCourse(
    id: json['id'] as String,
    title: json['title'] as String,
    provider: json['provider'] as String,
    description: json['description'] as String? ?? '',
    imageUrl: json['imageUrl'] as String?,
    category: json['category'] as String,
    keywords: (json['keywords'] as List? ?? const []).cast<String>(),
    campaign: json['campaign'] is Map
        ? CommercialCampaign.fromJson(
            Map<String, dynamic>.from(json['campaign'] as Map),
          )
        : null,
  );
}
