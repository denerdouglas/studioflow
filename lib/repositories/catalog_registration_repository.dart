import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/utils/id_generator.dart';
import '../database/database_service.dart';
import '../services/product_lookup_service.dart';
import '../services/session_controller.dart';

enum InventoryDestination { salon, store }

enum CatalogContributionDecision { sendForReview, doNotSend, askLater }

class LocalProductInput {
  final String? gtin;
  final String name;
  final String? brand;
  final String? imageUrl;
  final String description;
  final String category;
  final String unit;
  final double costPrice;
  final double salePrice;
  final double quantity;
  final double minimumStock;
  final String? batch;
  final DateTime? expiresAt;
  final String notes;
  final InventoryDestination destination;
  final CatalogContributionDecision contribution;
  final String source;

  const LocalProductInput({
    this.gtin,
    required this.name,
    this.brand,
    this.imageUrl,
    required this.description,
    required this.category,
    required this.unit,
    required this.costPrice,
    required this.salePrice,
    required this.quantity,
    required this.minimumStock,
    this.batch,
    this.expiresAt,
    required this.notes,
    required this.destination,
    required this.contribution,
    this.source = 'manual',
  });
}

class CatalogRegistrationRepository {
  final Future<Database> Function() _database;
  CatalogRegistrationRepository({Future<Database> Function()? databaseProvider})
    : _database = databaseProvider ?? (() => DatabaseService.instance.database);

  Future<String> save(LocalProductInput input) async {
    final user = SessionController.instance.usuario;
    if (user == null) throw StateError('Sessão não autenticada.');
    if (input.name.trim().isEmpty || input.category.trim().isEmpty) {
      throw StateError('Nome e categoria são obrigatórios.');
    }
    if ([
      input.costPrice,
      input.salePrice,
      input.quantity,
      input.minimumStock,
    ].any((value) => value < 0)) {
      throw StateError('Valores e quantidades não podem ser negativos.');
    }
    final normalized = input.gtin == null
        ? ''
        : ProductLookupService.normalizeGtin(input.gtin!);
    if (normalized.isNotEmpty &&
        !ProductLookupService.isValidGtin(normalized)) {
      throw const FormatException('Código GTIN inválido.');
    }
    final destination = input.destination == InventoryDestination.store
        ? 'loja'
        : 'salao';
    final now = DateTime.now().toUtc();
    final id = 'prd_${IdGenerator.temporal(now)}';
    final internalCode = normalized.isEmpty
        ? '${user.comercioId}_${destination}_${now.microsecondsSinceEpoch}'
        : null;
    final db = await _database();
    await db.transaction((txn) async {
      if (normalized.isNotEmpty) {
        final duplicate = await txn.query(
          'estoque',
          columns: ['id'],
          where: 'comercio_id = ? AND estoque_destino = ? AND codigo_barras = ?',
          whereArgs: [user.comercioId, destination, normalized],
          limit: 1,
        );
        if (duplicate.isNotEmpty) {
          throw StateError('Este código já existe no estoque escolhido.');
        }
      }
      await txn.insert('estoque', {
        'id': id,
        'comercio_id': user.comercioId,
        'estoque_destino': destination,
        'nome': input.name.trim(),
        'descricao': input.description.trim(),
        'categoria': input.category.trim(),
        'marca': input.brand?.trim(),
        'imagem': input.imageUrl,
        'codigo_interno': internalCode,
        'codigo_barras': normalized.isEmpty ? null : normalized,
        'tipo': 'produto',
        'modalidade': 'proprio',
        'custo_unitario': input.costPrice,
        'preco_venda': destination == 'loja' ? input.salePrice : 0,
        'margem': input.costPrice > 0 && destination == 'loja'
            ? ((input.salePrice - input.costPrice) / input.costPrice) * 100
            : 0,
        'quantidade_atual': input.quantity,
        'estoque_minimo': input.minimumStock,
        'quantidade_sugerida': 0,
        'unidade': input.unit.trim().isEmpty ? 'un' : input.unit.trim(),
        'quantidade_embalagem': 1,
        'lote': input.batch?.trim(),
        'data_validade': input.expiresAt?.toIso8601String(),
        'observacoes': input.notes.trim(),
        'origem_catalogo': input.source,
        'ativo': 1,
        'descontar_automaticamente': destination == 'loja' ? 1 : 0,
        'data_cadastro': now.toIso8601String(),
        'atualizado_em': now.toIso8601String(),
      });
      if (input.quantity > 0) {
        await txn.insert('movimentacoes_estoque', {
          'id': IdGenerator.temporal(),
          'comercio_id': user.comercioId,
          'item_estoque_id': id,
          'tipo': 'entrada',
          'quantidade': input.quantity,
          'quantidade_anterior': 0,
          'quantidade_posterior': input.quantity,
          'data': now.toIso8601String(),
          'motivo': 'Cadastro pelo catálogo inteligente',
          'usuario_responsavel_id': user.id,
          'origem': 'catalogo_inteligente',
        });
      }
      if (input.contribution == CatalogContributionDecision.sendForReview &&
          normalized.isNotEmpty) {
        final suggestionId = 'sug_${IdGenerator.temporal()}';
        final generalData = CatalogProduct(
          gtin: normalized,
          name: input.name.trim(),
          brand: input.brand?.trim(),
          category: input.category.trim(),
          description: input.description.trim(),
          imageUrl: input.imageUrl,
          physicalUnit: input.unit.trim(),
          source: 'manual',
          confidence: 0.25,
        );
        await txn.insert('catalogo_sugestoes', {
          'id': suggestionId,
          'comercio_id': user.comercioId,
          'usuario_id': user.id,
          'gtin': normalized,
          'dados_json': jsonEncode(generalData.toJson()),
          'consentimento': 1,
          'status': 'pendente',
          'criado_em': now.toIso8601String(),
        });
        await txn.insert('fila_sincronizacao', {
          'id': 'sync_$suggestionId',
          'comercio_id': user.comercioId,
          'unidade_id': null,
          'entidade': 'catalogo_sugestao',
          'entidade_id': suggestionId,
          'operacao': 'criar',
          'payload_json': jsonEncode(generalData.toJson()),
          'versao_local': 1,
          'status': 'pendente',
          'tentativas': 0,
          'criada_em': now.toIso8601String(),
          'atualizada_em': now.toIso8601String(),
        });
      }
    });
    return id;
  }
}
