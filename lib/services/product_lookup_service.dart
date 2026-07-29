import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../database/database_service.dart';
import 'backend_sync_service.dart';

class CatalogProduct {
  final String gtin;
  final String name;
  final String? brand;
  final String? category;
  final String? description;
  final String? imageUrl;
  final String? quantity;
  final String source;
  final double confidence;

  const CatalogProduct({
    required this.gtin,
    required this.name,
    this.brand,
    this.category,
    this.description,
    this.imageUrl,
    this.quantity,
    required this.source,
    required this.confidence,
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
    'confidence': confidence,
  };

  factory CatalogProduct.fromJson(Map<String, Object?> json) => CatalogProduct(
    gtin: json['gtin'] as String,
    name: json['name'] as String,
    brand: json['brand'] as String?,
    category: json['category'] as String?,
    description: json['description'] as String?,
    imageUrl: json['imageUrl'] as String?,
    quantity: json['quantity'] as String?,
    source: json['source'] as String? ?? 'cache',
    confidence: (json['confidence'] as num? ?? 0).toDouble(),
  );
}

abstract interface class ProductCatalogProvider {
  String get id;
  Future<CatalogProduct?> findByGtin(String gtin, {String? commerceId});
}

class LocalProductCatalogProvider implements ProductCatalogProvider {
  final Future<Database> Function() _database;
  LocalProductCatalogProvider({Future<Database> Function()? databaseProvider})
    : _database = databaseProvider ?? (() => DatabaseService.instance.database);

  @override
  String get id => 'local_salon';

  @override
  Future<CatalogProduct?> findByGtin(String gtin, {String? commerceId}) async {
    if (commerceId == null) return null;
    final db = await _database();
    final rows = await db.query(
      'estoque',
      where: 'comercio_id = ? AND codigo_barras = ? AND ativo = 1',
      whereArgs: [commerceId, gtin],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return CatalogProduct(
      gtin: gtin,
      name: row['nome'] as String,
      brand: row['marca'] as String?,
      category: row['categoria'] as String?,
      description: row['descricao'] as String?,
      imageUrl: row['imagem'] as String?,
      source: id,
      confidence: 1,
    );
  }
}

class StudioFlowCatalogProvider implements ProductCatalogProvider {
  final Future<Database> Function() _database;
  StudioFlowCatalogProvider({Future<Database> Function()? databaseProvider})
    : _database = databaseProvider ?? (() => DatabaseService.instance.database);

  @override
  String get id => 'studioflow_catalog';

  @override
  Future<CatalogProduct?> findByGtin(String gtin, {String? commerceId}) async {
    final db = await _database();
    final rows = await db.query(
      'catalogo_produtos',
      where: 'gtin = ? AND status = ?',
      whereArgs: [gtin, 'ativo'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return CatalogProduct(
      gtin: gtin,
      name: row['nome'] as String,
      brand: row['marca'] as String?,
      category: row['categoria'] as String?,
      description: row['descricao'] as String?,
      imageUrl: row['imagem_url'] as String?,
      source: id,
      confidence: (row['confianca'] as num? ?? 0).toDouble(),
    );
  }
}

/// Adaptador intencionalmente offline. Um backend poderá implementar este
/// contrato sem inserir token, chave ou scraping no aplicativo.
class CatalogProviderUnavailable implements Exception {
  final String message;
  const CatalogProviderUnavailable(this.message);
  @override
  String toString() => message;
}

class OfficialProductCatalogProvider implements ProductCatalogProvider {
  final BackendSyncService _backend;

  OfficialProductCatalogProvider({BackendSyncService? backend})
    : _backend = backend ?? BackendSyncService();

  @override
  String get id => 'official_backend';

  @override
  Future<CatalogProduct?> findByGtin(String gtin, {String? commerceId}) async {
    if (commerceId == null) return null;
    try {
      final response = await _backend.buscarProdutoGtin(commerceId, gtin);
      if (response['found'] != true || response['product'] is! Map) return null;
      final product = Map<String, Object?>.from(response['product'] as Map);
      return CatalogProduct(
        gtin: gtin,
        name: product['name'] as String,
        brand: product['brand'] as String?,
        category: product['category'] as String?,
        description: product['description'] as String?,
        imageUrl: product['imageUrl'] as String?,
        quantity: product['quantity'] as String?,
        source: 'Open Beauty Facts / Open Products Facts (ODbL 1.0)',
        confidence: 0.85,
      );
    } catch (error) {
      throw CatalogProviderUnavailable(
        'Catálogo externo indisponível: $error Cadastre o produto manualmente.',
      );
    }
  }
}

class CommunityProductCatalogProvider extends StudioFlowCatalogProvider {
  CommunityProductCatalogProvider({super.databaseProvider});

  @override
  String get id => 'community_approved';
}

class MockProductCatalogProvider implements ProductCatalogProvider {
  final Map<String, CatalogProduct> products;
  const MockProductCatalogProvider([this.products = const {}]);

  @override
  String get id => 'mock';

  @override
  Future<CatalogProduct?> findByGtin(String gtin, {String? commerceId}) async =>
      products[gtin];
}

class ProductLookupResult {
  final CatalogProduct? product;
  final String normalizedGtin;
  final List<String> consultedProviders;
  final bool fromCache;

  const ProductLookupResult({
    required this.product,
    required this.normalizedGtin,
    required this.consultedProviders,
    required this.fromCache,
  });
}

class ProductLookupService {
  final Future<Database> Function() _database;
  final List<ProductCatalogProvider> providers;
  final Duration cacheDuration;

  ProductLookupService({
    Future<Database> Function()? databaseProvider,
    List<ProductCatalogProvider>? providers,
    this.cacheDuration = const Duration(days: 30),
  }) : _database =
           databaseProvider ?? (() => DatabaseService.instance.database),
       providers =
           providers ??
           [
             LocalProductCatalogProvider(databaseProvider: databaseProvider),
             StudioFlowCatalogProvider(databaseProvider: databaseProvider),
             OfficialProductCatalogProvider(),
             CommunityProductCatalogProvider(
               databaseProvider: databaseProvider,
             ),
           ];

  static String normalizeGtin(String input) =>
      input.replaceAll(RegExp(r'[^0-9]'), '');

  static bool isValidGtin(String input) {
    final value = normalizeGtin(input);
    if (!const {8, 12, 13, 14}.contains(value.length)) return false;
    final digits = value.split('').map(int.parse).toList();
    final check = digits.removeLast();
    var sum = 0;
    for (var i = digits.length - 1, position = 0; i >= 0; i--, position++) {
      sum += digits[i] * (position.isEven ? 3 : 1);
    }
    return (10 - (sum % 10)) % 10 == check;
  }

  Future<ProductLookupResult> lookup(
    String rawGtin, {
    required String commerceId,
  }) async {
    final gtin = normalizeGtin(rawGtin);
    if (!isValidGtin(gtin)) {
      throw const FormatException('Código GTIN inválido. Confira os dígitos.');
    }
    final consulted = <String>[];
    final local = providers
        .where((provider) => provider.id == 'local_salon')
        .firstOrNull;
    if (local != null) {
      consulted.add(local.id);
      final product = await local.findByGtin(gtin, commerceId: commerceId);
      if (product != null) {
        return ProductLookupResult(
          product: product,
          normalizedGtin: gtin,
          consultedProviders: consulted,
          fromCache: false,
        );
      }
    }
    final cached = await _readCache(gtin);
    if (cached != null && cached.source != 'local_salon') {
      return ProductLookupResult(
        product: cached,
        normalizedGtin: gtin,
        consultedProviders: [...consulted, 'cache'],
        fromCache: true,
      );
    }
    for (final provider in providers.where(
      (provider) => provider.id != 'local_salon',
    )) {
      consulted.add(provider.id);
      final product = await provider.findByGtin(gtin, commerceId: commerceId);
      if (product != null) {
        await _writeCache(product);
        return ProductLookupResult(
          product: product,
          normalizedGtin: gtin,
          consultedProviders: consulted,
          fromCache: false,
        );
      }
    }
    return ProductLookupResult(
      product: null,
      normalizedGtin: gtin,
      consultedProviders: consulted,
      fromCache: false,
    );
  }

  Future<CatalogProduct?> _readCache(String gtin) async {
    final db = await _database();
    final rows = await db.query(
      'catalogo_cache',
      where: 'gtin = ? AND expira_em > ?',
      whereArgs: [gtin, DateTime.now().toUtc().toIso8601String()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CatalogProduct.fromJson(
      (jsonDecode(rows.first['dados_json'] as String) as Map)
          .cast<String, Object?>(),
    );
  }

  Future<void> _writeCache(CatalogProduct product) async {
    final db = await _database();
    final now = DateTime.now().toUtc();
    await db.insert('catalogo_cache', {
      'gtin': product.gtin,
      'dados_json': jsonEncode(product.toJson()),
      'fonte': product.source,
      'expira_em': now.add(cacheDuration).toIso8601String(),
      'atualizado_em': now.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
