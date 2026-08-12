import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:sqflite/sqflite.dart';

import '../database/database_service.dart';
import '../core/validation/gtin_validator.dart';
import 'backend_sync_service.dart';

class CatalogProduct {
  final String gtin;
  final String name;
  final String? brand;
  final String? category;
  final String? description;
  final String? imageUrl;
  final String? quantity;
  final String? physicalUnit;
  final double? contentPerUnit;
  final String? contentUnit;
  final String? localProductId;
  final String? localDestination;
  final String source;
  final double? confidence;
  final bool exactMatch;

  const CatalogProduct({
    required this.gtin,
    required this.name,
    this.brand,
    this.category,
    this.description,
    this.imageUrl,
    this.quantity,
    this.physicalUnit,
    this.contentPerUnit,
    this.contentUnit,
    this.localProductId,
    this.localDestination,
    required this.source,
    this.confidence,
    this.exactMatch = true,
  });

  Map<String, Object?> toJson() => {
    'gtin': gtin,
    'name': name,
    'brand': brand,
    'category': category,
    'description': description,
    'imageUrl': imageUrl,
    'quantity': quantity,
    'physicalUnit': physicalUnit,
    'contentPerUnit': contentPerUnit,
    'contentUnit': contentUnit,
    'localProductId': localProductId,
    'localDestination': localDestination,
    'source': source,
    'confidence': confidence,
    'exactMatch': exactMatch,
  };

  factory CatalogProduct.fromJson(Map<String, Object?> json) => CatalogProduct(
    gtin: (json['barcode'] ?? json['gtin']) as String,
    name: json['name'] as String,
    brand: json['brand'] as String?,
    category: json['category'] as String?,
    description: json['description'] as String?,
    imageUrl: json['imageUrl'] as String?,
    quantity: json['quantity'] as String?,
    physicalUnit:
        (json['physical_unit'] ?? json['physicalUnit'] ?? json['unit'])
            as String?,
    contentPerUnit:
        ((json['content_per_unit'] ?? json['contentPerUnit'] ?? 1) as num)
            .toDouble(),
    contentUnit: (json['content_unit'] ?? json['contentUnit']) as String?,
    localProductId: json['localProductId'] as String?,
    localDestination: json['localDestination'] as String?,
    source: json['source'] as String? ?? 'cache',
    confidence: (json['confidence'] as num?)?.toDouble(),
    exactMatch: json['exactMatch'] as bool? ?? true,
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
      where: 'comercio_id = ? AND codigo_barras = ?',
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
      physicalUnit: row['unidade'] as String?,
      contentPerUnit: (row['conteudo_por_unidade'] as num? ?? 1).toDouble(),
      contentUnit: row['unidade_conteudo'] as String?,
      localProductId: row['id'] as String,
      localDestination: row['estoque_destino'] as String?,
      source: 'business',
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
      physicalUnit:
          row['unidade_fisica'] as String? ?? row['unidade'] as String?,
      contentPerUnit: (row['conteudo_por_unidade'] as num? ?? 1).toDouble(),
      contentUnit: row['unidade_conteudo'] as String?,
      source: 'studioflow',
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

      debugPrint('==================================');
      debugPrint('RESPOSTA DO CATÁLOGO: $response');
      debugPrint('==================================');

      if (response['found'] != true || response['product'] is! Map) {
        return null;
      }
      final product = Map<String, Object?>.from(response['product'] as Map);
      final returnedGtin = product['barcode'] ?? product['gtin'];
      if (returnedGtin is! String ||
          !GtinValidator.isExactMatch(gtin, returnedGtin) ||
          response['approximate'] == true ||
          response['exact'] == false) {
        return null;
      }
      return CatalogProduct(
        gtin: GtinValidator.normalize(returnedGtin),
        name: product['name'] as String,
        brand: product['brand'] as String?,
        category: product['category'] as String?,
        description: product['description'] as String?,
        imageUrl: product['imageUrl'] as String?,
        quantity: product['quantity'] as String?,
        physicalUnit:
            product['physical_unit'] as String? ?? product['unit'] as String?,
        contentPerUnit: (product['content_per_unit'] as num? ?? 1).toDouble(),
        contentUnit: product['content_unit'] as String?,
        source: response['source'] as String? ?? 'external',
        // O backend atual não fornece uma medição de confiança verificável.
        confidence: null,
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
           ];

  static String normalizeGtin(String input) => GtinValidator.normalize(input);

  static bool isValidGtin(String input) => GtinValidator.isValid(input);

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
      if (_isExactProduct(gtin, product)) {
        return ProductLookupResult(
          product: product,
          normalizedGtin: gtin,
          consultedProviders: consulted,
          fromCache: false,
        );
      }
    }
    final shared = providers
        .where((provider) => provider.id == 'studioflow_catalog')
        .firstOrNull;
    if (shared != null) {
      consulted.add(shared.id);
      final product = await shared.findByGtin(gtin, commerceId: commerceId);
      if (_isExactProduct(gtin, product)) {
        await _writeCache(product!);
        return ProductLookupResult(
          product: product,
          normalizedGtin: gtin,
          consultedProviders: consulted,
          fromCache: false,
        );
      }
    }
    final cached = await _readCache(gtin);
    if (cached != null &&
        _isExactProduct(gtin, cached) &&
        cached.source != 'business' &&
        cached.source != 'studioflow') {
      return ProductLookupResult(
        product: cached,
        normalizedGtin: gtin,
        consultedProviders: [...consulted, 'cache'],
        fromCache: true,
      );
    }
    for (final provider in providers.where(
      (provider) =>
          provider.id != 'local_salon' && provider.id != 'studioflow_catalog',
    )) {
      consulted.add(provider.id);
      final product = await provider.findByGtin(gtin, commerceId: commerceId);
      if (_isExactProduct(gtin, product)) {
        await _writeCache(product!);
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

  static bool _isExactProduct(String requested, CatalogProduct? product) =>
      product != null &&
      product.exactMatch &&
      GtinValidator.isExactMatch(requested, product.gtin);

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
