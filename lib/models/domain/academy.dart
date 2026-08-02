class AcademyCategory {
  final String id;
  final String name;
  final String? icon;
  final int orderIndex;
  final String status;
  final String? description;

  const AcademyCategory({
    required this.id,
    required this.name,
    this.icon,
    this.orderIndex = 0,
    this.status = 'active',
    this.description,
  });

  factory AcademyCategory.fromJson(Map<String, dynamic> json) {
    return AcademyCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      icon: json['icon'] as String?,
      orderIndex: json['orderIndex'] as int? ?? 0,
      status: json['status'] as String? ?? 'active',
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'icon': icon,
      'orderIndex': orderIndex,
      'status': status,
      'description': description,
    };
  }
}

class AcademyCourse {
  final String id;
  final String title;
  final String? subtitle;
  final String description;
  final String? coverImageUrl;
  final String categoryId;
  final String authorName;
  final String authorAvatarUrl;
  final int durationMinutes;
  final String difficultyLevel;
  final double? price;
  final String currency;
  final double? rating;
  final int totalReviews;
  final String? clickId;
  final String publicationStatus;
  final DateTime publishedAt;
  final DateTime updatedAt;

  const AcademyCourse({
    required this.id,
    required this.title,
    this.subtitle,
    required this.description,
    this.coverImageUrl,
    required this.categoryId,
    required this.authorName,
    required this.authorAvatarUrl,
    required this.durationMinutes,
    required this.difficultyLevel,
    this.price,
    required this.currency,
    this.rating,
    required this.totalReviews,
    this.clickId,
    required this.publicationStatus,
    required this.publishedAt,
    required this.updatedAt,
  });

  factory AcademyCourse.fromJson(Map<String, dynamic> json) {
    return AcademyCourse(
      id: json['id'] as String,
      title: json['title'] as String,
      subtitle: json['subtitle'] as String?,
      description: json['description'] as String? ?? '',
      coverImageUrl: json['coverImageUrl'] as String?,
      categoryId: json['categoryId'] as String,
      authorName: json['authorName'] as String? ?? '',
      authorAvatarUrl: json['authorAvatarUrl'] as String? ?? '',
      durationMinutes: json['durationMinutes'] as int? ?? 0,
      difficultyLevel: json['difficultyLevel'] as String? ?? 'beginner',
      price: json['price'] != null ? (json['price'] as num).toDouble() : null,
      currency: json['currency'] as String? ?? 'BRL',
      rating: json['rating'] != null ? (json['rating'] as num).toDouble() : null,
      totalReviews: json['totalReviews'] as int? ?? 0,
      clickId: json['clickId'] as String?,
      publicationStatus: json['publicationStatus'] as String? ?? 'published',
      publishedAt: json['publishedAt'] != null 
          ? DateTime.parse(json['publishedAt'] as String) 
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null 
          ? DateTime.parse(json['updatedAt'] as String) 
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'description': description,
      'coverImageUrl': coverImageUrl,
      'categoryId': categoryId,
      'authorName': authorName,
      'authorAvatarUrl': authorAvatarUrl,
      'durationMinutes': durationMinutes,
      'difficultyLevel': difficultyLevel,
      'price': price,
      'currency': currency,
      'rating': rating,
      'totalReviews': totalReviews,
      'clickId': clickId,
      'publicationStatus': publicationStatus,
      'publishedAt': publishedAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  bool get isComingSoon => publicationStatus == 'coming_soon';
}
