import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/models/domain/acesso.dart';
import 'package:studioflow/repositories/acesso_repository.dart';
import 'package:studioflow/repositories/customer_cart_repository.dart';

void main() {
  sqfliteFfiInit();

  test('carrinho aceita e baixa somente estoque da loja', () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 6,
        onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
        onCreate: DatabaseSchemaLatest.criar,
      ),
    );
    addTearDown(db.close);
    final owner = await AcessoRepository(databaseProvider: () async => db)
        .cadastrarComercio(
          const CadastroComercioEntrada(
            nomeComercio: 'Cart Test',
            nomeExibicao: 'Cart',
            responsavel: 'Owner',
            telefone: '11999999999',
            email: 'cart@studioflow.test',
            senha: 'Senha@123',
            permanecerConectado: false,
          ),
        );
    final now = DateTime.now().toIso8601String();
    for (final item in [('store', 'loja'), ('salon', 'salao')]) {
      await db.insert('estoque', {
        'id': item.$1,
        'comercio_id': owner.comercioId,
        'estoque_destino': item.$2,
        'nome': item.$1,
        'categoria': 'Teste',
        'tipo': 'produto',
        'quantidade_atual': 10,
        'estoque_minimo': 1,
        'unidade': 'un',
        'custo_unitario': 2,
        'preco_venda': 5,
        'data_cadastro': now,
      });
    }
    final repository = CustomerCartRepository(databaseProvider: () async => db);
    final cart = await repository.create(owner.comercioId);

    await expectLater(
      repository.addItem(cartId: cart, productId: 'salon', quantity: 1),
      throwsStateError,
    );
    await repository.addItem(cartId: cart, productId: 'store', quantity: 3);
    await repository.checkout(cart);

    final store = await db.query(
      'estoque',
      where: 'id = ?',
      whereArgs: ['store'],
    );
    final salon = await db.query(
      'estoque',
      where: 'id = ?',
      whereArgs: ['salon'],
    );
    expect(store.single['quantidade_atual'], 7);
    expect(salon.single['quantidade_atual'], 10);
  });
}
