import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';

final class CatalogProductData {
  final String gtin;
  final String name;
  final String? brand;
  final String? category;
  final String? description;
  final String? imageUrl;
  final String? quantity;
  final String source;

  const CatalogProductData({
    required this.gtin,
    required this.name,
    this.brand,
    this.category,
    this.description,
    this.imageUrl,
    this.quantity,
    required this.source,
  });

  Map<String, Object?> toJson() => {
    'gtin': gtin,
    'name': name,
    'brand': brand,
    'category': category,
    'description': description,
    'imageUrl': imageUrl,
    'quantity': quantity,
    'source': source,
    'sourceAttribution': 'Open Beauty Facts / Open Products Facts',
    'sourceLicense': 'ODbL 1.0',
    'sourceUrl': 'https://world.openfoodfacts.org',
  };

  factory CatalogProductData.fromJson(Map<String, Object?> value) =>
      CatalogProductData(
        gtin: value['gtin'] as String,
        name: value['name'] as String,
        brand: value['brand'] as String?,
        category: value['category'] as String?,
        description: value['description'] as String?,
        imageUrl: value['imageUrl'] as String?,
        quantity: value['quantity'] as String?,
        source: value['source'] as String? ?? 'open_facts',
      );
}

final class CatalogCacheEntry {
  final String status;
  final CatalogProductData? product;
  final DateTime expiresAt;

  const CatalogCacheEntry({
    required this.status,
    required this.product,
    required this.expiresAt,
  });
}

abstract interface class CatalogStore {
  Future<CatalogCacheEntry?> cached(String gtin, DateTime now);
  Future<void> save({
    required String gtin,
    required String status,
    required CatalogProductData? product,
    required DateTime expiresAt,
  });
  Future<void> log({
    required String businessId,
    required String userId,
    required String gtin,
    required String result,
    required int durationMs,
    String? errorCode,
  });
  Future<void> close();
}

final class MemoryCatalogStore implements CatalogStore {
  final Map<String, CatalogCacheEntry> entries = {};
  final List<Map<String, Object?>> logs = [];

  @override
  Future<CatalogCacheEntry?> cached(String gtin, DateTime now) async {
    final entry = entries[gtin];
    return entry != null && entry.expiresAt.isAfter(now) ? entry : null;
  }

  @override
  Future<void> save({
    required String gtin,
    required String status,
    required CatalogProductData? product,
    required DateTime expiresAt,
  }) async {
    entries[gtin] = CatalogCacheEntry(
      status: status,
      product: product,
      expiresAt: expiresAt,
    );
  }

  @override
  Future<void> log({
    required String businessId,
    required String userId,
    required String gtin,
    required String result,
    required int durationMs,
    String? errorCode,
  }) async {
    logs.add({
      'businessId': businessId,
      'userId': userId,
      'gtin': gtin,
      'result': result,
      'durationMs': durationMs,
      'errorCode': errorCode,
    });
  }

  @override
  Future<void> close() async {}
}

final class PostgresCatalogStore implements CatalogStore {
  final Pool _pool;
  PostgresCatalogStore._(this._pool);
  factory PostgresCatalogStore.fromUrl(String url) =>
      PostgresCatalogStore._(Pool.withUrl(url));

  @override
  Future<CatalogCacheEntry?> cached(String gtin, DateTime now) async {
    final result = await _pool.execute(
      Sql.named(
        'SELECT status,payload,expires_at FROM catalog_gtin_cache WHERE gtin=@gtin AND expires_at>@now',
      ),
      parameters: {'gtin': gtin, 'now': now},
    );
    if (result.isEmpty) return null;
    final row = result.single.toColumnMap();
    final payload = _map(row['payload']);
    return CatalogCacheEntry(
      status: row['status'] as String,
      product: payload.isEmpty ? null : CatalogProductData.fromJson(payload),
      expiresAt: row['expires_at'] as DateTime,
    );
  }

  @override
  Future<void> save({
    required String gtin,
    required String status,
    required CatalogProductData? product,
    required DateTime expiresAt,
  }) async {
    await _pool.execute(
      Sql.named(
        '''INSERT INTO catalog_gtin_cache(gtin,status,payload,source,source_license,expires_at)
        VALUES(@gtin,@status,CAST(@payload AS jsonb),'open_facts','ODbL-1.0',@expiresAt)
        ON CONFLICT(gtin) DO UPDATE SET status=EXCLUDED.status,payload=EXCLUDED.payload,
          source=EXCLUDED.source,source_license=EXCLUDED.source_license,
          expires_at=EXCLUDED.expires_at,updated_at=now()''',
      ),
      parameters: {
        'gtin': gtin,
        'status': status,
        'payload': jsonEncode(product?.toJson() ?? const {}),
        'expiresAt': expiresAt,
      },
    );
  }

  @override
  Future<void> log({
    required String businessId,
    required String userId,
    required String gtin,
    required String result,
    required int durationMs,
    String? errorCode,
  }) async {
    await _pool.runTx((tx) async {
      await tx.execute(
        Sql.named("SELECT set_config('app.business_id', @businessId, true)"),
        parameters: {'businessId': businessId},
      );
      await tx.execute(
        Sql.named(
          '''INSERT INTO catalog_gtin_logs(business_id,user_id,gtin,result,source,duration_ms,error_code)
          VALUES(@businessId,@userId,@gtin,@result,'open_facts',@durationMs,@errorCode)''',
        ),
        parameters: {
          'businessId': businessId,
          'userId': userId,
          'gtin': gtin,
          'result': result,
          'durationMs': durationMs,
          'errorCode': errorCode,
        },
      );
    });
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is Map) return Map<String, Object?>.from(value);
    if (value is String) {
      return Map<String, Object?>.from(jsonDecode(value) as Map);
    }
    return const {};
  }

  @override
  Future<void> close() => _pool.close();
}

final class CatalogLookupService {
  final CatalogStore store;
  final Uri baseUrl;
  final String userAgent;
  final http.Client client;
  final Duration positiveCache;
  final Duration negativeCache;

  CatalogLookupService({
    required this.store,
    required this.baseUrl,
    required this.userAgent,
    http.Client? client,
    this.positiveCache = const Duration(days: 30),
    this.negativeCache = const Duration(hours: 24),
  }) : client = client ?? http.Client();

  Future<CatalogProductData?> lookup({
    required String businessId,
    required String userId,
    required String gtin,
  }) async {
    final watch = Stopwatch()..start();
    if (!_validGtin(gtin)) {
      await store.log(
        businessId: businessId,
        userId: userId,
        gtin: gtin,
        result: 'invalid',
        durationMs: watch.elapsedMilliseconds,
      );
      throw const FormatException('GTIN inválido.');
    }
    final now = DateTime.now().toUtc();
    final cached = await store.cached(gtin, now);
    if (cached != null) {
      await store.log(
        businessId: businessId,
        userId: userId,
        gtin: gtin,
        result: 'cache_hit',
        durationMs: watch.elapsedMilliseconds,
      );
      return cached.product;
    }
    try {
      final endpoint = baseUrl.replace(
        path:
            '${baseUrl.path.replaceAll(RegExp(r'/$'), '')}/api/v3/product/$gtin',
        queryParameters: {
          'product_type': 'all',
          'fields':
              'code,product_name,product_name_pt,brands,categories,categories_tags,quantity,image_front_url,image_url,generic_name,generic_name_pt',
        },
      );
      final response = await client
          .get(
            endpoint,
            headers: {'user-agent': userAgent, 'accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 404) {
        await store.save(
          gtin: gtin,
          status: 'not_found',
          product: null,
          expiresAt: now.add(negativeCache),
        );
        await store.log(
          businessId: businessId,
          userId: userId,
          gtin: gtin,
          result: 'not_found',
          durationMs: watch.elapsedMilliseconds,
        );
        return null;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('catalog_http_${response.statusCode}');
      }
      final body = Map<String, Object?>.from(jsonDecode(response.body) as Map);
      final raw = body['product'];
      if (raw is! Map) {
        await store.save(
          gtin: gtin,
          status: 'not_found',
          product: null,
          expiresAt: now.add(negativeCache),
        );
        await store.log(
          businessId: businessId,
          userId: userId,
          gtin: gtin,
          result: 'not_found',
          durationMs: watch.elapsedMilliseconds,
        );
        return null;
      }
      final product = Map<String, Object?>.from(raw);
      final name = _first(product, ['product_name_pt', 'product_name']);
      if (name == null) return null;
      final result = CatalogProductData(
        gtin: gtin,
        name: name,
        brand: _first(product, ['brands']),
        category: _first(product, ['categories']),
        description: _first(product, ['generic_name_pt', 'generic_name']),
        imageUrl: _safeHttps(_first(product, ['image_front_url', 'image_url'])),
        quantity: _first(product, ['quantity']),
        source: 'open_facts',
      );
      await store.save(
        gtin: gtin,
        status: 'found',
        product: result,
        expiresAt: now.add(positiveCache),
      );
      await store.log(
        businessId: businessId,
        userId: userId,
        gtin: gtin,
        result: 'found',
        durationMs: watch.elapsedMilliseconds,
      );
      return result;
    } on Object catch (error) {
      await store.log(
        businessId: businessId,
        userId: userId,
        gtin: gtin,
        result: 'provider_error',
        durationMs: watch.elapsedMilliseconds,
        errorCode: error.toString().substring(
          0,
          min(120, error.toString().length),
        ),
      );
      rethrow;
    }
  }

  static String? _first(Map<String, Object?> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  static String? _safeHttps(String? value) {
    final uri = value == null ? null : Uri.tryParse(value);
    return uri?.scheme == 'https' ? uri.toString() : null;
  }

  static bool _validGtin(String value) {
    if (!RegExp(r'^\d{8}$|^\d{12,14}$').hasMatch(value)) return false;
    final digits = value.split('').map(int.parse).toList();
    final check = digits.removeLast();
    var sum = 0;
    for (var i = digits.length - 1, p = 0; i >= 0; i--, p++) {
      sum += digits[i] * (p.isEven ? 3 : 1);
    }
    return (10 - sum % 10) % 10 == check;
  }
}
