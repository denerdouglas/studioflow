import 'package:sqflite/sqflite.dart';

import '../core/utils/id_generator.dart';
import '../database/database_service.dart';
import '../services/session_controller.dart';

class MenuItem {
  final String id;
  final String name;
  final String description;
  final String category;
  final double price;
  final bool active;

  const MenuItem({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.price,
    required this.active,
  });

  factory MenuItem.fromMap(Map<String, Object?> map) => MenuItem(
    id: map['id'] as String,
    name: map['nome'] as String,
    description: map['descricao'] as String? ?? '',
    category: map['categoria'] as String? ?? 'Outros',
    price: (map['preco'] as num? ?? 0).toDouble(),
    active: map['ativo'] == 1,
  );
}

class MenuComplement {
  final String id;
  final String itemId;
  final String name;
  final double additionalPrice;
  final bool active;

  const MenuComplement({
    required this.id,
    required this.itemId,
    required this.name,
    required this.additionalPrice,
    required this.active,
  });
}

class MenuRepository {
  final Future<Database> Function() _database;
  MenuRepository({Future<Database> Function()? databaseProvider})
    : _database = databaseProvider ?? (() => DatabaseService.instance.database);

  String get _commerceId {
    final user = SessionController.instance.usuario;
    if (user == null) throw StateError('Sessão não autenticada.');
    return user.comercioId;
  }

  Future<List<MenuItem>> list({bool includeInactive = true}) async {
    final db = await _database();
    final rows = await db.query(
      'cardapio_itens',
      where: includeInactive
          ? 'comercio_id = ?'
          : 'comercio_id = ? AND ativo = 1',
      whereArgs: [_commerceId],
      orderBy: 'ativo DESC, categoria, nome COLLATE NOCASE',
    );
    return rows.map(MenuItem.fromMap).toList();
  }

  Future<void> save({
    String? id,
    required String name,
    required String description,
    required String category,
    required double price,
    required bool active,
  }) async {
    if (name.trim().isEmpty || category.trim().isEmpty) {
      throw StateError('Nome e categoria são obrigatórios.');
    }
    if (price < 0) throw StateError('O preço não pode ser negativo.');
    final db = await _database();
    final now = DateTime.now().toUtc().toIso8601String();
    final itemId = id ?? 'menu_${IdGenerator.temporal()}';
    final data = <String, Object?>{
      'nome': name.trim(),
      'descricao': description.trim(),
      'preco': price,
      'categoria': category.trim(),
      'ativo': active ? 1 : 0,
      'atualizado_em': now,
    };
    if (id == null) {
      await db.insert('cardapio_itens', {
        'id': itemId,
        'comercio_id': _commerceId,
        ...data,
        'criado_em': now,
      });
    } else {
      final changed = await db.update(
        'cardapio_itens',
        data,
        where: 'id = ? AND comercio_id = ?',
        whereArgs: [id, _commerceId],
      );
      if (changed == 0) {
        throw StateError('Item do cardápio não encontrado.');
      }
    }
  }

  Future<void> setActive(String id, bool active) async {
    final db = await _database();
    await db.update(
      'cardapio_itens',
      {
        'ativo': active ? 1 : 0,
        'atualizado_em': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [id, _commerceId],
    );
  }

  Future<void> delete(String id) async {
    final db = await _database();
    await db.delete(
      'cardapio_itens',
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [id, _commerceId],
    );
  }

  Future<List<MenuComplement>> complements(String itemId) async {
    final db = await _database();
    final rows = await db.query(
      'cardapio_complementos',
      where: 'item_id = ? AND comercio_id = ?',
      whereArgs: [itemId, _commerceId],
      orderBy: 'ativo DESC, nome COLLATE NOCASE',
    );
    return rows
        .map(
          (row) => MenuComplement(
            id: row['id'] as String,
            itemId: row['item_id'] as String,
            name: row['nome'] as String,
            additionalPrice: (row['preco_adicional'] as num).toDouble(),
            active: row['ativo'] == 1,
          ),
        )
        .toList();
  }

  Future<void> addComplement(
    String itemId, {
    required String name,
    required double additionalPrice,
  }) async {
    if (name.trim().isEmpty || additionalPrice < 0) {
      throw StateError('Informe um complemento e preço válidos.');
    }
    final db = await _database();
    await db.insert('cardapio_complementos', {
      'id': 'comp_${IdGenerator.temporal()}',
      'comercio_id': _commerceId,
      'item_id': itemId,
      'nome': name.trim(),
      'preco_adicional': additionalPrice,
      'ativo': 1,
    });
  }
}
