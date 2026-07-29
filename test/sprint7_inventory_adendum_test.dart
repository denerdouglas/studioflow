import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/models/domain/acesso.dart';
import 'package:studioflow/repositories/acesso_repository.dart';
import 'package:studioflow/repositories/inventory_transfer_repository.dart';
import 'package:studioflow/services/product_lookup_service.dart';
import 'package:studioflow/services/session_controller.dart';

void main() {
  sqfliteFfiInit();

  test('formatos GTIN válidos e inválidos são reconhecidos', () {
    expect(ProductLookupService.isValidGtin('96385074'), isTrue);
    expect(ProductLookupService.isValidGtin('036000291452'), isTrue);
    expect(ProductLookupService.isValidGtin('7894900011517'), isTrue);
    expect(ProductLookupService.isValidGtin('12345678901231'), isTrue);
    expect(ProductLookupService.isValidGtin('7894900011518'), isFalse);
  });

  test('transferência separa saldos e registra duas movimentações', () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 10,
        onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
        onCreate: DatabaseSchemaLatest.criar,
      ),
    );
    addTearDown(db.close);
    final access = AcessoRepository(databaseProvider: () async => db);
    final owner = await access.cadastrarComercio(
      const CadastroComercioEntrada(
        nomeComercio: 'Studio Estoque',
        nomeExibicao: 'Studio Estoque',
        responsavel: 'Dona Estoque',
        telefone: '11999999999',
        email: 'estoque@studioflow.test',
        senha: 'Senha@123',
        permanecerConectado: false,
      ),
    );
    SessionController.instance.entrar(owner);
    final now = DateTime.now().toIso8601String();
    await db.insert('estoque', {
      'id': 'produto_salao',
      'comercio_id': owner.comercioId,
      'estoque_destino': 'salao',
      'nome': 'Shampoo profissional',
      'categoria': 'Produtos',
      'tipo': 'produto',
      'codigo_barras': '7894900011517',
      'quantidade_atual': 10,
      'estoque_minimo': 2,
      'unidade': 'un',
      'custo_unitario': 10,
      'data_cadastro': now,
    });

    final transfer = InventoryTransferRepository(
      databaseProvider: () async => db,
    );
    await transfer.transferToStore(
      sourceProductId: 'produto_salao',
      quantity: 3,
      reason: 'Reposição de exposição',
    );

    final products = await db.query(
      'estoque',
      where: 'comercio_id=?',
      whereArgs: [owner.comercioId],
      orderBy: 'estoque_destino',
    );
    expect(products, hasLength(2));
    expect(
      products
          .where((row) => row['estoque_destino'] == 'salao')
          .single['quantidade_atual'],
      7.0,
    );
    expect(
      products
          .where((row) => row['estoque_destino'] == 'loja')
          .single['quantidade_atual'],
      3.0,
    );
    expect(await db.query('transferencias_estoque'), hasLength(1));
    expect(
      await db.query(
        'movimentacoes_estoque',
        where: "origem='transferencia_estoque'",
      ),
      hasLength(2),
    );
  });
}
