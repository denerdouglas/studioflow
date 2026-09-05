import 'commercial_campaigns.dart';

String normalizeBarcode(String value) => value.replaceAll(RegExp(r'\D'), '');

bool isValidGlobalBarcode(String value) {
  final normalized = normalizeBarcode(value);
  if (![8, 12, 13, 14].contains(normalized.length)) return false;
  final digits = normalized.split('').map(int.parse).toList();
  final check = digits.removeLast();
  var sum = 0;
  for (var i = digits.length - 1, position = 0; i >= 0; i--, position++) {
    sum += digits[i] * (position.isEven ? 3 : 1);
  }
  return (10 - sum % 10) % 10 == check;
}

final class GlobalProduct {
  final String id;
  final String barcode;
  final String brand;
  final String name;
  final String? variant;
  final String category;
  final String? description;
  final String? imageUrl;
  final String? size;
  final bool active;
  final List<String> keywords;
  final bool verified;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const GlobalProduct({
    required this.id,
    required this.barcode,
    required this.brand,
    required this.name,
    this.variant,
    required this.category,
    this.description,
    this.imageUrl,
    this.size,
    required this.active,
    this.keywords = const [],
    required this.verified,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'barcode': barcode,
    'brand': brand,
    'name': name,
    'variant': variant,
    'category': category,
    'description': description,
    'imageUrl': imageUrl,
    'size': size,
    'active': active,
    'keywords': keywords,
    'verified': verified,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}

final class ProductSuggestion {
  final String id;
  final String barcode;
  final String businessId;
  final String name;
  final String? brand;
  final String? variant;
  final String? category;
  final String status;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final DateTime createdAt;

  const ProductSuggestion({
    required this.id,
    required this.barcode,
    required this.businessId,
    required this.name,
    this.brand,
    this.variant,
    this.category,
    required this.status,
    this.reviewedBy,
    this.reviewedAt,
    required this.createdAt,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'barcode': barcode,
    'name': name,
    'brand': brand,
    'variant': variant,
    'category': category,
    'status': status,
    'reviewedAt': reviewedAt?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
  };
}

final class GlobalCourse {
  final String id;
  final String title;
  final String provider;
  final String description;
  final String? imageUrl;
  final String category;
  final List<String> keywords;
  final bool active;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const GlobalCourse({
    required this.id,
    required this.title,
    required this.provider,
    required this.description,
    this.imageUrl,
    required this.category,
    this.keywords = const [],
    required this.active,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, Object?> toJson({CommercialCampaign? campaign}) => {
    'id': id,
    'title': title,
    'provider': provider,
    'description': description,
    'imageUrl': imageUrl,
    'category': category,
    'keywords': keywords,
    'active': active,
    if (campaign != null) 'campaign': campaign.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}

abstract interface class GlobalContentStore {
  Future<List<GlobalProduct>> listProducts();
  Future<GlobalProduct?> productByBarcode(String barcode);
  Future<GlobalProduct?> productById(String id);
  Future<void> saveProduct(GlobalProduct product);
  Future<ProductSuggestion?> pendingSuggestion(
    String businessId,
    String barcode,
  );
  Future<ProductSuggestion?> suggestionById(String id);
  Future<List<ProductSuggestion>> listSuggestions({String? status});
  Future<void> saveSuggestion(ProductSuggestion suggestion);
  Future<GlobalCourse?> courseById(String id);
  Future<List<GlobalCourse>> listCourses();
  Future<List<GlobalCourse>> searchCourses(String query);
  Future<void> saveCourse(GlobalCourse course);
}

final class GlobalContentMemoryStore implements GlobalContentStore {
  final Map<String, GlobalProduct> products = {};
  final Map<String, ProductSuggestion> suggestions = {};
  final Map<String, GlobalCourse> courses = {};

  @override
  Future<List<GlobalProduct>> listProducts() async => products.values.toList();

  @override
  Future<GlobalProduct?> productByBarcode(String barcode) async => products
      .values
      .where((item) => item.barcode == barcode && item.active)
      .firstOrNull;
  @override
  Future<GlobalProduct?> productById(String id) async => products[id];
  @override
  Future<void> saveProduct(GlobalProduct product) async {
    final duplicate = products.values.any(
      (item) => item.id != product.id && item.barcode == product.barcode,
    );
    if (duplicate) throw StateError('barcode_already_exists');
    products[product.id] = product;
  }

  @override
  Future<ProductSuggestion?> pendingSuggestion(
    String businessId,
    String barcode,
  ) async => suggestions.values
      .where(
        (item) =>
            item.businessId == businessId &&
            item.barcode == barcode &&
            item.status == 'pending',
      )
      .firstOrNull;
  @override
  Future<ProductSuggestion?> suggestionById(String id) async => suggestions[id];
  @override
  Future<List<ProductSuggestion>> listSuggestions({String? status}) async =>
      suggestions.values
          .where((item) => status == null || item.status == status)
          .toList();
  @override
  Future<void> saveSuggestion(ProductSuggestion suggestion) async {
    suggestions[suggestion.id] = suggestion;
  }

  @override
  Future<GlobalCourse?> courseById(String id) async => courses[id];
  @override
  Future<List<GlobalCourse>> listCourses() async => courses.values.toList();
  @override
  Future<List<GlobalCourse>> searchCourses(String query) async {
    final normalized = query.trim().toLowerCase();
    return courses.values.where((item) {
      if (!item.active) return false;
      final haystack = [
        item.title,
        item.provider,
        item.description,
        item.category,
        ...item.keywords,
      ].join(' ').toLowerCase();
      return normalized.isEmpty || haystack.contains(normalized);
    }).toList();
  }

  @override
  Future<void> saveCourse(GlobalCourse course) async {
    courses[course.id] = course;
  }
}
