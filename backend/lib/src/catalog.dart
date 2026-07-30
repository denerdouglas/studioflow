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
  final String? unit;
  final String source;

  const CatalogProductData({
    required this.gtin,
    required this.name,
    this.brand,
    this.category,
    this.description,
    this.imageUrl,
    this.quantity,
    this.unit,
    required this.source,
  });

  Map<String, Object?> toJson() => {
    'barcode': gtin,
    'gtin': gtin,
    'name': name,
    'brand': brand,
    'category': category,
    'description': description,
    'imageUrl': imageUrl,
    'quantity': quantity,
    'unit': unit,
    'source': source,
    if (source == 'external') ...{
      'sourceAttribution': 'Open Beauty Facts / Open Products Facts',
      'sourceLicense': 'ODbL 1.0',
      'sourceUrl': 'https://world.openfoodfacts.org',
    },
  };

  factory CatalogProductData.fromJson(Map<String, Object?> value) =>
      CatalogProductData(
        gtin: (value['barcode'] ?? value['gtin']) as String,
        name: value['name'] as String,
        brand: value['brand'] as String?,
        category: value['category'] as String?,
        description: value['description'] as String?,
        imageUrl: value['imageUrl'] as String?,
        quantity: value['quantity'] as String?,
        unit: value['unit'] as String?,
        source: value['source'] as String? ?? 'external',
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
  Future<CatalogProductData?> businessProduct(String businessId, String gtin);
  Future<CatalogProductData?> sharedProduct(String gtin);
  Future<void> contribute({
    required CatalogProductData product,
    required String businessId,
    required String userId,
  });
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
  final Map<String, CatalogProductData> businessProducts = {};
  final Map<String, CatalogProductData> sharedProducts = {};
  final List<Map<String, Object?>> logs = [];

  @override
  Future<CatalogProductData?> businessProduct(
    String businessId,
    String gtin,
  ) async => businessProducts['$businessId:$gtin'];

  @override
  Future<CatalogProductData?> sharedProduct(String gtin) async =>
      sharedProducts[gtin];

  @override
  Future<void> contribute({
    required CatalogProductData product,
    required String businessId,
    required String userId,
  }) async {
    sharedProducts[product.gtin] = CatalogProductData(
      gtin: product.gtin,
      name: product.name,
      brand: product.brand,
      category: product.category,
      description: product.description,
      imageUrl: product.imageUrl,
      unit: product.unit,
      source: 'studioflow',
    );
  }

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
  Future<CatalogProductData?> businessProduct(
    String businessId,
    String gtin,
  ) async {
    return _pool.runTx((tx) async {
      await tx.execute(
        Sql.named("SELECT set_config('app.business_id', @businessId, true)"),
        parameters: {'businessId': businessId},
      );
      final result = await tx.execute(
        Sql.named('''SELECT payload FROM sync_records
          WHERE business_id=@businessId AND deleted=FALSE
            AND entity IN ('estoque','produtos_estoque','produtos_loja')
            AND payload->>'codigo_barras'=@gtin
          ORDER BY updated_at DESC LIMIT 1'''),
        parameters: {'businessId': businessId, 'gtin': gtin},
      );
      if (result.isEmpty) return null;
      final payload = _map(result.single.toColumnMap()['payload']);
      final name = payload['nome']?.toString().trim();
      if (name == null || name.isEmpty) return null;
      return CatalogProductData(
        gtin: gtin,
        name: name,
        brand: _text(payload['marca']),
        category: _text(payload['categoria']),
        description: _text(payload['descricao']),
        imageUrl: _https(_text(payload['imagem'])),
        unit: _text(payload['unidade']),
        source: 'business',
      );
    });
  }

  @override
  Future<CatalogProductData?> sharedProduct(String gtin) async {
    final result = await _pool.execute(
      Sql.named('''SELECT barcode,name,brand,description,category,image_url,unit
        FROM catalog_products_shared
        WHERE barcode=@gtin AND status='active' LIMIT 1'''),
      parameters: {'gtin': gtin},
    );
    if (result.isEmpty) return null;
    final row = result.single.toColumnMap();
    return CatalogProductData(
      gtin: row['barcode'] as String,
      name: row['name'] as String,
      brand: row['brand'] as String?,
      category: row['category'] as String?,
      description: row['description'] as String?,
      imageUrl: row['image_url'] as String?,
      unit: row['unit'] as String?,
      source: 'studioflow',
    );
  }

  @override
  Future<void> contribute({
    required CatalogProductData product,
    required String businessId,
    required String userId,
  }) async {
    await _pool.execute(
      Sql.named('''INSERT INTO catalog_products_shared
        (barcode,name,brand,description,category,image_url,unit,source,status,
         contributed_by_business_id,contributed_by_user_id)
        VALUES(@barcode,@name,@brand,@description,@category,@imageUrl,@unit,
          'manual','active',@businessId,@userId)
        ON CONFLICT(barcode) DO UPDATE SET
          name=COALESCE(NULLIF(catalog_products_shared.name,''),EXCLUDED.name),
          brand=COALESCE(catalog_products_shared.brand,EXCLUDED.brand),
          description=COALESCE(catalog_products_shared.description,EXCLUDED.description),
          category=COALESCE(catalog_products_shared.category,EXCLUDED.category),
          image_url=COALESCE(catalog_products_shared.image_url,EXCLUDED.image_url),
          unit=COALESCE(catalog_products_shared.unit,EXCLUDED.unit),
          updated_at=now()'''),
      parameters: {
        'barcode': product.gtin,
        'name': product.name.trim(),
        'brand': product.brand,
        'description': product.description,
        'category': product.category,
        'imageUrl': product.imageUrl,
        'unit': product.unit,
        'businessId': businessId,
        'userId': userId,
      },
    );
  }

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

  static String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static String? _https(String? value) {
    final uri = value == null ? null : Uri.tryParse(value);
    return uri?.scheme == 'https' ? uri.toString() : null;
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
  final String? userAgent;
  final http.Client client;
  final Duration positiveCache;
  final Duration negativeCache;

  CatalogLookupService({
    required this.store,
    required this.baseUrl,
    this.userAgent,
    http.Client? client,
    this.positiveCache = const Duration(days: 30),
    this.negativeCache = const Duration(hours: 24),
  }) : client = client ?? http.Client();

  Future<void> contribute({
    required String businessId,
    required String userId,
    required CatalogProductData product,
  }) async {
    if (!_validGtin(product.gtin) || product.name.trim().isEmpty) {
      throw const FormatException('Produto compartilhado inválido.');
    }
    await store.contribute(
      product: CatalogProductData(
        gtin: product.gtin,
        name: product.name.trim(),
        brand: _clean(product.brand),
        category: _clean(product.category),
        description: _clean(product.description),
        imageUrl: _safeHttps(product.imageUrl),
        unit: _clean(product.unit),
        source: 'studioflow',
      ),
      businessId: businessId,
      userId: userId,
    );
  }

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
    final business = await store.businessProduct(businessId, gtin);
    if (business != null) {
      await store.log(
        businessId: businessId,
        userId: userId,
        gtin: gtin,
        result: 'found',
        durationMs: watch.elapsedMilliseconds,
      );
      return business;
    }
    final shared = await store.sharedProduct(gtin);
    if (shared != null) {
      await store.log(
        businessId: businessId,
        userId: userId,
        gtin: gtin,
        result: 'found',
        durationMs: watch.elapsedMilliseconds,
      );
      return shared;
    }
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
    if (userAgent == null || userAgent!.trim().isEmpty) {
      throw StateError('catalog_external_not_configured');
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
            headers: {'user-agent': userAgent!, 'accept': 'application/json'},
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
      final quantity = _first(product, ['quantity']);
      final result = CatalogProductData(
        gtin: gtin,
        name: name,
        brand: _first(product, ['brands']),
        category: _first(product, ['categories']),
        description: _first(product, ['generic_name_pt', 'generic_name']),
        imageUrl: _safeHttps(_first(product, ['image_front_url', 'image_url'])),
        quantity: quantity,
        unit: _unitFromQuantity(quantity),
        source: 'external',
      );
      await store.save(
  gtin: gtin,
  status: 'found',
  product: result,
  expiresAt: now.add(positiveCache),
);

// Alimenta automaticamente a base compartilhada do StudioFlow.
// Se o produto já existir, o método contribute faz o merge/atualização.
await store.contribute(
  product: CatalogProductData(
    gtin: result.gtin,
    name: result.name,
    brand: result.brand,
    category: result.category,
    description: result.description,
    imageUrl: result.imageUrl,
    quantity: result.quantity,
    unit: result.unit,
    source: 'studioflow',
  ),
  businessId: businessId,
  userId: userId,
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

  static String? _clean(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  static String? _first(Map<String, Object?> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  static String? _unitFromQuantity(String? quantity) {
    final match = RegExp(
      r'\b(ml|l|g|kg|un|und|unidades?)\b',
      caseSensitive: false,
    ).firstMatch(quantity ?? '');
    if (match == null) return null;
    final value = match.group(1)!.toLowerCase();
    return value.startsWith('un') ? 'un' : value;
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
