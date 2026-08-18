import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/models/domain/acesso.dart';
import 'package:studioflow/repositories/central_comandas_repository.dart';
import 'package:studioflow/repositories/comanda_loja_repository.dart';
import 'package:studioflow/services/session_controller.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late ComandaLojaRepository repo;
  late CentralComandasRepository central;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 42,
        onCreate: DatabaseSchemaLatest.criar,
      ),
    );
    SessionController.instance.entrar(_owner());
    repo = ComandaLojaRepository(databaseProvider: () async => db);
    central = CentralComandasRepository(
      databaseProvider: () async => db,
      comercioId: 'commerce-1',
    );
    await _seed(db);
  });

  tearDown(() => db.close());

  test(
    'adiciona, remove, altera quantidade e recalcula comanda aberta',
    () async {
      final id = await repo.criar(clienteId: 'client-1');
      await repo.adicionarProduto(id, 'product-1', quantidade: 2);
      final original = await repo.itens(id);
      await repo.reconciliarItens(id, [
        {...original.single, 'quantidade': 3.0},
        {'produto_id': 'product-2', 'quantidade': 1.0, 'valor_unitario': 30.0},
      ]);
      var detail = await central.detalhe(id, origem: 'comanda');
      expect(detail['total'], 90.0);
      expect(detail['itens'], hasLength(2));

      await repo.reconciliarItens(id, [
        (detail['itens'] as List<Map<String, Object?>>).last,
      ]);
      detail = await central.detalhe(id, origem: 'comanda');
      expect(detail['total'], 30.0);
      expect(detail['itens'], hasLength(1));
      expect(
        (await db.query(
          'estoque',
          where: "id='product-1'",
        )).single['quantidade_atual'],
        10.0,
      );
    },
  );

  test(
    'edição finalizada baixa e devolve somente a diferença uma vez',
    () async {
      final id = await _finalized(repo);
      expect(await _stock(db, 'product-1'), 8.0);
      var items = await repo.itens(id);
      await repo.reconciliarItens(id, [
        {...items.single, 'quantidade': 3.0},
      ]);
      expect(await _stock(db, 'product-1'), 7.0);
      await repo.reconciliarItens(id, [
        {...(await repo.itens(id)).single, 'quantidade': 3.0},
      ]);
      expect(await _stock(db, 'product-1'), 7.0);

      items = await repo.itens(id);
      await repo.reconciliarItens(id, [
        {'produto_id': 'product-2', 'quantidade': 1.0, 'valor_unitario': 30.0},
      ]);
      expect(await _stock(db, 'product-1'), 10.0);
      expect(await _stock(db, 'product-2'), 4.0);
      expect(items, isNotEmpty);
    },
  );

  test('peça consignada é restaurada ao removê-la da venda', () async {
    await _seedFinalizedPiece(db);
    await repo.reconciliarItens('cmd-piece', [
      {'produto_id': 'product-2', 'quantidade': 1.0, 'valor_unitario': 30.0},
    ]);
    final piece = (await db.query(
      'pecas_unicas',
      where: "id='piece-1'",
    )).single;
    expect(piece['status'], 'disponivel');
    final consignment = (await db.query(
      'consignacoes',
      where: "id='lot-1'",
    )).single;
    expect(consignment['quantidade_vendida'], 0);
    expect(consignment['quantidade_disponivel'], 1);
  });

  test(
    'dois pagamentos preservam histórico, data escolhida e status final',
    () async {
      final id = await _finalized(repo, initialPayment: 0);
      final first = DateTime(2026, 8, 18, 18, 38);
      final second = DateTime(2026, 8, 20, 10, 20);
      await repo.registrarPagamento(id, 20, 'pix', dataPagamento: first);
      await repo.registrarPagamento(id, 20, 'dinheiro', dataPagamento: second);
      final detail = await central.detalhe(id, origem: 'comanda');
      final payments = detail['pagamentos'] as List<Map<String, Object?>>;
      expect(payments, hasLength(2));
      expect(payments.first['forma'], 'pix');
      expect(
        DateTime.parse('${payments.first['registrado_em']}').toLocal(),
        first,
      );
      expect(detail['status_central'], 'paga');
      expect(DateTime.parse('${detail['data_pagamento']}').toLocal(), second);
    },
  );

  test(
    'correção estorna e relança sem duplicar valor financeiro ativo',
    () async {
      final id = await _finalized(repo, initialPayment: 40);
      final original = (await db.query(
        'comanda_loja_pagamentos',
        where: 'comanda_id=?',
        whereArgs: [id],
      )).single;
      final correctedDate = DateTime(2026, 8, 19, 9, 15);
      await repo.corrigirPagamento(
        id,
        original['id'] as String,
        novaForma: 'dinheiro',
        novaData: correctedDate,
      );
      final payments = await db.query(
        'comanda_loja_pagamentos',
        where: 'comanda_id=?',
        whereArgs: [id],
      );
      expect(payments.where((p) => p['status'] == 'pago'), hasLength(1));
      expect(payments.where((p) => p['status'] == 'estornado'), hasLength(1));
      expect(
        payments.singleWhere((p) => p['status'] == 'pago')['forma'],
        'dinheiro',
      );
      final active = await db.rawQuery(
        "SELECT COALESCE(SUM(valor),0) total FROM movimentacoes_financeiras WHERE entidade_origem='comanda' AND entidade_origem_id=? AND status='pago'",
        [id],
      );
      expect(active.single['total'], 40.0);
    },
  );

  test('troca de cliente atualiza mesma comanda, venda e conta', () async {
    final id = await _finalized(repo, initialPayment: 0);
    await repo.editar(comandaId: id, clienteId: 'client-2');
    expect(
      (await central.listar(clienteId: 'client-1')).where((r) => r['id'] == id),
      isEmpty,
    );
    expect(
      (await central.listar(clienteId: 'client-2')).where((r) => r['id'] == id),
      hasLength(1),
    );
    final command = (await db.query(
      'comandas_loja',
      where: 'id=?',
      whereArgs: [id],
    )).single;
    final sale = (await db.query(
      'pdv_vendas',
      where: 'id=?',
      whereArgs: [command['venda_id']],
    )).single;
    expect(sale['cliente_id'], 'client-2');
  });

  test('cancelamento finalizado devolve estoque sem delete físico', () async {
    final id = await _finalized(repo, initialPayment: 40);
    await repo.estornar(id, 'Erro operacional');
    expect(await _stock(db, 'product-1'), 10.0);
    expect(
      (await db.query(
        'comandas_loja',
        where: 'id=?',
        whereArgs: [id],
      )).single['status'],
      'estornada',
    );
    expect(await repo.itens(id), isNotEmpty);
  });

  test('aumento de total pago cria saldo na conta vinculada', () async {
    final id = await _finalized(repo, initialPayment: 40);
    final current = (await repo.itens(id)).single;
    await repo.reconciliarItens(id, [
      current,
      {'produto_id': 'product-2', 'quantidade': 1.0, 'valor_unitario': 30.0},
    ]);
    final account = (await db.query(
      'contas_receber_loja',
      where: 'comanda_id=?',
      whereArgs: [id],
    )).single;
    expect(account['valor_total'], 70.0);
    expect(account['valor_recebido'], 40.0);
    expect(account['status'], 'parcialmente_paga');
  });

  test('UI contém ações, formatação brasileira e não imprime ID técnico', () {
    final source = File(
      'lib/screens/comandas_loja_page.dart',
    ).readAsStringSync();
    expect(source, contains("label: const Text('Editar comanda')"));
    expect(source, contains("label: const Text('Registrar pagamento')"));
    expect(source, contains("label: const Text('Excluir / Cancelar')"));
    expect(source, contains("DateFormat(\"dd/MM/yyyy 'às' HH:mm\")"));
    expect(source, isNot(contains("Responsável: \${data['profissional_id']}")));
  });
}

Future<String> _finalized(
  ComandaLojaRepository repo, {
  double initialPayment = 0,
}) async {
  final id = await repo.criar(
    clienteId: 'client-1',
    vencimento: DateTime(2026, 8, 25),
  );
  await repo.adicionarProduto(id, 'product-1', quantidade: 2);
  await repo.finalizar(
    id,
    pagamentoInicial: initialPayment,
    formaPagamento: 'pix',
    vencimento: DateTime(2026, 8, 25),
    dataPagamento: DateTime(2026, 8, 18, 12),
  );
  return id;
}

Future<double> _stock(Database db, String id) async =>
    ((await db.query(
              'estoque',
              where: 'id=?',
              whereArgs: [id],
            )).single['quantidade_atual']
            as num)
        .toDouble();

Future<void> _seed(Database db) async {
  final now = DateTime.utc(2026, 8, 18).toIso8601String();
  for (final client in const [
    ('client-1', 'Maria', '11999999999'),
    ('client-2', 'Ana', '11888888888'),
  ]) {
    await db.insert('clientes', {
      'id': client.$1,
      'nome': client.$2,
      'whatsapp': client.$3,
      'comercio_id': 'commerce-1',
      'data_cadastro': now,
      'ativo': 1,
    });
  }
  for (final product in const [
    ('product-1', 'Brinco', 'COD-1', 20.0, 10.0),
    ('product-2', 'Pulseira', 'COD-2', 30.0, 5.0),
  ]) {
    await db.insert('estoque', {
      'id': product.$1,
      'nome': product.$2,
      'categoria': 'joias',
      'tipo': 'produto',
      'quantidade_atual': product.$5,
      'estoque_minimo': 0,
      'unidade': 'un',
      'preco_venda': product.$4,
      'codigo_interno': product.$3,
      'estoque_destino': 'loja',
      'comercio_id': 'commerce-1',
      'ativo': 1,
      'data_cadastro': now,
    });
  }
}

Future<void> _seedFinalizedPiece(Database db) async {
  const now = '2026-08-18T12:00:00.000Z';
  await db.insert('fornecedores', {
    'id': 'supplier-1',
    'comercio_id': 'commerce-1',
    'nome': 'Fornecedor',
    'ativo': 1,
    'criado_em': now,
    'atualizado_em': now,
  });
  await db.insert('consignacoes', {
    'id': 'lot-1',
    'comercio_id': 'commerce-1',
    'fornecedor_id': 'supplier-1',
    'status': 'aberta',
    'quantidade_recebida': 1,
    'quantidade_disponivel': 0,
    'quantidade_vendida': 1,
    'valor_vendido': 50.0,
    'recebida_em': now,
    'criado_em': now,
  });
  await db.insert('pecas_unicas', {
    'id': 'piece-1',
    'comercio_id': 'commerce-1',
    'codigo_exclusivo': '526839',
    'nome': 'Brinco consignado',
    'custo': 20.0,
    'preco': 50.0,
    'lote_id': 'lot-1',
    'status': 'vendida',
    'data_cadastro': now,
  });
  await db.insert('pdv_vendas', {
    'id': 'sale-piece',
    'comercio_id': 'commerce-1',
    'profissional_id': 'user-1',
    'cliente_id': 'client-1',
    'valor_total': 50.0,
    'data_venda': now,
    'status': 'concluida',
  });
  await db.insert('pdv_venda_itens', {
    'id': 'sale-piece-item',
    'pdv_venda_id': 'sale-piece',
    'produto_id': 'piece-1',
    'quantidade': 1.0,
    'valor_unitario': 50.0,
  });
  await db.insert('comandas_loja', {
    'id': 'cmd-piece',
    'numero': '20260099',
    'comercio_id': 'commerce-1',
    'cliente_id': 'client-1',
    'status': 'aguardando_pagamento',
    'subtotal': 50.0,
    'desconto': 0.0,
    'total': 50.0,
    'valor_pago': 0.0,
    'vencimento': '2026-08-25T00:00:00.000Z',
    'venda_id': 'sale-piece',
    'criado_em': now,
    'atualizado_em': now,
  });
  await db.insert('comanda_loja_itens', {
    'id': 'cmd-piece-item',
    'comanda_id': 'cmd-piece',
    'comercio_id': 'commerce-1',
    'produto_id': 'piece-1',
    'codigo': '526839',
    'nome': 'Brinco consignado',
    'quantidade': 1.0,
    'valor_unitario': 50.0,
    'subtotal': 50.0,
  });
}

UsuarioAcesso _owner() => UsuarioAcesso(
  id: 'user-1',
  comercioId: 'commerce-1',
  codigoComercio: 'SFTEST',
  nomeComercio: 'Studio Teste',
  nomeExibicao: 'Studio Teste',
  nome: 'Dono',
  telefone: '11999999999',
  emailLogin: 'dono@teste.local',
  funcao: FuncaoUsuario.dono,
  ativo: true,
  permissoes: ModuloPermissao.values.toSet(),
  acoes: AcaoPermissao.values.toSet(),
);
