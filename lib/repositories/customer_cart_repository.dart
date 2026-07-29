import 'package:sqflite/sqflite.dart';

import '../core/utils/id_generator.dart';
import '../database/database_service.dart';

class CustomerCartRepository {
  final Future<Database> Function() _database;
  CustomerCartRepository({Future<Database> Function()? databaseProvider})
    : _database = databaseProvider ?? (() => DatabaseService.instance.database);

  Future<String> create(String commerceId, {String? customerId}) async {
    final db = await _database();
    final now = DateTime.now().toUtc().toIso8601String();
    final id = 'cart_${IdGenerator.temporal()}';
    await db.insert('carrinhos', {
      'id': id,
      'comercio_id': commerceId,
      'cliente_id': customerId,
      'status': 'aberto',
      'criado_em': now,
      'atualizado_em': now,
    });
    return id;
  }

  Future<void> addItem({
    required String cartId,
    required String productId,
    required double quantity,
  }) async {
    if (quantity <= 0) throw StateError('Quantidade inválida.');
    final db = await _database();
    final cart = await db.query(
      'carrinhos',
      where: 'id = ? AND status = ?',
      whereArgs: [cartId, 'aberto'],
      limit: 1,
    );
    if (cart.isEmpty) throw StateError('Carrinho não está aberto.');
    final product = await db.query(
      'estoque',
      columns: ['id', 'preco_venda', 'quantidade_atual'],
      where:
          "id = ? AND comercio_id = ? AND estoque_destino = 'loja' AND ativo = 1",
      whereArgs: [productId, cart.first['comercio_id']],
      limit: 1,
    );
    if (product.isEmpty) {
      throw StateError(
        'Somente produtos da Loja do Salão podem ir ao carrinho.',
      );
    }
    if ((product.first['quantidade_atual'] as num).toDouble() < quantity) {
      throw StateError('Estoque insuficiente.');
    }
    await db.insert('carrinho_itens', {
      'id': 'cartitem_${IdGenerator.temporal()}',
      'carrinho_id': cartId,
      'produto_id': productId,
      'quantidade': quantity,
      'preco_unitario': (product.first['preco_venda'] as num).toDouble(),
    });
  }

  Future<void> checkout(String cartId) async {
    final db = await _database();
    await db.transaction((txn) async {
      final carts = await txn.query(
        'carrinhos',
        where: 'id = ? AND status = ?',
        whereArgs: [cartId, 'aberto'],
        limit: 1,
      );
      if (carts.isEmpty) throw StateError('Carrinho não está aberto.');
      final commerceId = carts.first['comercio_id'] as String;
      final items = await txn.query(
        'carrinho_itens',
        where: 'carrinho_id = ?',
        whereArgs: [cartId],
      );
      if (items.isEmpty) throw StateError('Carrinho vazio.');
      for (final item in items) {
        final products = await txn.query(
          'estoque',
          columns: ['quantidade_atual'],
          where:
              "id = ? AND comercio_id = ? AND estoque_destino = 'loja' AND ativo = 1",
          whereArgs: [item['produto_id'], commerceId],
          limit: 1,
        );
        if (products.isEmpty) {
          throw StateError('Produto da loja não encontrado.');
        }
        final current = (products.first['quantidade_atual'] as num).toDouble();
        final quantity = (item['quantidade'] as num).toDouble();
        if (current < quantity) {
          throw StateError('Estoque insuficiente.');
        }
        await txn.update(
          'estoque',
          {'quantidade_atual': current - quantity},
          where: "id = ? AND comercio_id = ? AND estoque_destino = 'loja'",
          whereArgs: [item['produto_id'], commerceId],
        );
      }
      await txn.update(
        'carrinhos',
        {
          'status': 'finalizado_local',
          'atualizado_em': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [cartId],
      );
    });
  }
}
