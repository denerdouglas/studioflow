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
  final DateTime? startsAt;
  final DateTime? endsAt;
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
    this.startsAt,
    this.endsAt,
    this.globalProductId,
    this.courseId,
  });

  factory CommercialCampaign.fromJson(Map<String, dynamic> json) =>
      CommercialCampaign(
        id: json['id'] as String,
        title: json['title'] as String,
        subtitle: json['subtitle'] as String?,
        description: json['description'] as String? ?? '',
        imageUrl: json['imageUrl'] as String?,
        destinationUrl: json['destinationUrl'] as String,
        category: json['category'] as String? ?? 'outros',
        sourceType: json['sourceType'] as String,
        priceCents: json['price'] as int?,
        originalPriceCents: json['originalPrice'] as int?,
        badge: json['badge'] as String?,
        ctaText: json['ctaText'] as String? ?? 'Saiba mais',
        priority: json['priority'] as int? ?? 0,
        startsAt: _date(json['startsAt']),
        endsAt: _date(json['endsAt']),
        globalProductId: json['globalProductId'] as String?,
        courseId: json['courseId'] as String?,
      );

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  String get disclosure => switch (sourceType) {
    'rolg_academy' => 'ROLG Academy',
    'affiliate' => 'Publicidade',
    'partner' => 'Oferta de parceiro',
    _ => 'StudioFlow',
  };

  bool isValidAt(DateTime now) =>
      (startsAt == null || !startsAt!.isAfter(now)) &&
      (endsAt == null || endsAt!.isAfter(now));

  static Uri? safeDestination(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        {'localhost', '127.0.0.1', '::1'}.contains(uri.host.toLowerCase())) {
      return null;
    }
    return uri;
  }
}
