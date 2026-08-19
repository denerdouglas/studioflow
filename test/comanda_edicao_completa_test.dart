import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/models/domain/acesso.dart';
import 'package:studioflow/models/domain/loja.dart';
import 'package:studioflow/repositories/central_comandas_repository.dart';
import 'package:studioflow/repositories/cliente_360_repository.dart';
import 'package:studioflow/repositories/comanda_loja_repository.dart';
import 'package:studioflow/repositories/loja_repository.dart';
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
    expect(
      source,
      contains("label: const Text('Registrar / editar pagamento')"),
    );
    expect(source, contains("label: const Text('Cancelar / excluir')"));
    expect(source, contains('PopupMenuButton<String>'));
    expect(source, contains("child: Text('Pagamento')"));
    expect(source, contains("DateFormat(\"dd/MM/yyyy 'às' HH:mm\")"));
    expect(source, isNot(contains("Responsável: \${data['profissional_id']}")));
  });

  test('Nova Venda expõe Pago/Pendente, data e vencimento', () {
    final source = File('lib/screens/vendas_loja_page.dart').readAsStringSync();
    expect(source, contains("labelText: 'Situação do pagamento'"));
    expect(source, contains("value: 'Pago'"));
    expect(source, contains("value: 'Pendente'"));
    expect(source, contains("? 'Data do pagamento'"));
    expect(source, contains(": 'Data de vencimento'"));
  });

  test('Pix pendente não cria pagamento e cria conta com vencimento', () async {
    final id = await repo.criar(
      clienteId: 'client-1',
      vencimento: DateTime(2026, 9, 1),
    );
    await repo.adicionarProduto(id, 'product-1', quantidade: 1);
    await repo.finalizar(
      id,
      pagamentoInicial: 0,
      formaPagamento: 'pix',
      vencimento: DateTime(2026, 9, 1),
    );
    expect(
      await db.query(
        'comanda_loja_pagamentos',
        where: 'comanda_id=?',
        whereArgs: [id],
      ),
      isEmpty,
    );
    final account = (await db.query(
      'contas_receber_loja',
      where: 'comanda_id=?',
      whereArgs: [id],
    )).single;
    expect(account['status'], 'pendente');
    expect('${account['vencimento']}', contains('2026-09-01'));
  });

  test('Pix pago persiste a data escolhida pela Nova Venda', () async {
    final loja = LojaRepository(databaseProvider: () async => db);
    final product = await loja.buscarCodigo('COD-1');
    final selected = DateTime(2026, 8, 17, 14, 25);
    final id = await loja.finalizarVenda(
      itens: [ItemCarrinho(product!, 1)],
      desconto: 0,
      pagamentos: const {'pix': 20},
      profissionalId: 'user-1',
      clienteId: 'client-1',
      dataPagamento: selected,
    );
    final finance = (await db.query(
      'movimentacoes_financeiras',
      where: 'entidade_origem_id=?',
      whereArgs: [id],
    )).single;
    expect(DateTime.parse('${finance['data']}').toLocal(), selected);
  });

  test('data final é a do pagamento que zerou o saldo', () async {
    final id = await _finalized(repo, initialPayment: 0);
    final first = DateTime(2026, 8, 20, 10);
    final closing = DateTime(2026, 8, 18, 9);
    await repo.registrarPagamento(id, 10, 'pix', dataPagamento: first);
    await repo.registrarPagamento(id, 30, 'dinheiro', dataPagamento: closing);
    final detail = await central.detalhe(id, origem: 'comanda');
    expect(DateTime.parse('${detail['data_pagamento']}').toLocal(), closing);
  });

  test('correção de valor reabre saldo e cria conta auditável', () async {
    final id = await _finalized(repo, initialPayment: 40);
    final original = (await db.query(
      'comanda_loja_pagamentos',
      where: 'comanda_id=?',
      whereArgs: [id],
    )).single;
    await repo.corrigirPagamento(
      id,
      original['id'] as String,
      novaForma: 'dinheiro',
      novaData: DateTime(2026, 8, 19, 9),
      novoValor: 30,
    );
    final command = (await db.query(
      'comandas_loja',
      where: 'id=?',
      whereArgs: [id],
    )).single;
    expect(command['valor_pago'], 30.0);
    expect(command['status'], 'parcialmente_paga');
    expect(
      await db.query('comanda_auditoria', where: "acao='correcao_pagamento'"),
      isNotEmpty,
    );
    expect(
      await db.query(
        'contas_receber_loja',
        where: 'comanda_id=?',
        whereArgs: [id],
      ),
      hasLength(1),
    );
  });

  test('31 comanda atual do Cliente 360 é clicável', () {
    final sources = _cliente360Sources();
    expect(sources, everyElement(contains('onTap: legado ? null')));
  });

  test('32 Cliente 360 abre o mesmo detalhe operacional da Central', () {
    final sources = _cliente360Sources();
    expect(sources, everyElement(contains('VendaCentralDetalhePage(')));
    expect(sources, everyElement(isNot(contains('ComandaDetalhePage('))));
  });

  test('33 Cliente 360 encaminha o mesmo comanda_id', () async {
    final id = await repo.criar(clienteId: 'client-1');
    final resumo = await _cliente360(db).carregar('client-1');
    expect(resumo.historicoCompras.single['id'], id);
    expect(
      _cliente360Sources(),
      everyElement(contains("venda['id'] as String")),
    );
  });

  test('34 edição pelo Cliente 360 altera a mesma comanda', () async {
    final id = await repo.criar(clienteId: 'client-1');
    await repo.editar(comandaId: id, observacoes: 'Editada pelo Cliente 360');
    final row = (await db.query(
      'comandas_loja',
      where: 'id=?',
      whereArgs: [id],
    )).single;
    expect(row['observacoes'], 'Editada pelo Cliente 360');
    expect(await db.query('comandas_loja'), hasLength(1));
  });

  test('35 adicionar item pelo Cliente 360 reflete na Central', () async {
    final id = await repo.criar(clienteId: 'client-1');
    await repo.adicionarProduto(id, 'product-1');
    final cliente = await _cliente360(db).carregar('client-1');
    final centralRow = (await central.listar(clienteId: 'client-1')).single;
    expect(cliente.historicoCompras.single['id'], centralRow['id']);
    expect(cliente.historicoCompras.single['total'], centralRow['total']);
  });

  test('36 remover item pelo Cliente 360 reflete na Central', () async {
    final id = await repo.criar(clienteId: 'client-1');
    await repo.adicionarProduto(id, 'product-1');
    await repo.adicionarProduto(id, 'product-2');
    final items = await repo.itens(id);
    await repo.reconciliarItens(id, [
      items.singleWhere((item) => item['produto_id'] == 'product-2'),
    ]);
    final cliente = await _cliente360(db).carregar('client-1');
    expect(cliente.historicoCompras.single['total'], 30.0);
    expect(
      (await central.detalhe(id, origem: 'comanda'))['itens'],
      hasLength(1),
    );
  });

  test('37 pagamento pelo Cliente 360 reflete em Contas a Receber', () async {
    final id = await _finalized(repo, initialPayment: 0);
    await repo.registrarPagamento(id, 40, 'pix');
    final account = (await db.query(
      'contas_receber_loja',
      where: 'comanda_id=?',
      whereArgs: [id],
    )).single;
    expect(account['status'], 'paga');
    expect(account['valor_recebido'], 40.0);
  });

  test('38 data escolhida aparece no Cliente 360 e no detalhe', () async {
    final id = await _finalized(repo, initialPayment: 0);
    final selected = DateTime(2026, 8, 20, 14, 30);
    await repo.registrarPagamento(id, 40, 'pix', dataPagamento: selected);
    final cliente = await _cliente360(db).carregar('client-1');
    final detalhe = await central.detalhe(id, origem: 'comanda');
    expect(
      cliente.historicoCompras.single['data_pagamento'],
      detalhe['data_pagamento'],
    );
    expect(DateTime.parse('${detalhe['data_pagamento']}').toLocal(), selected);
  });

  test('39 status Pago Pendente Parcial permanece sincronizado', () async {
    final id = await _finalized(repo, initialPayment: 0);
    expect(
      (await _cliente360(
        db,
      ).carregar('client-1')).historicoCompras.single['status_central'],
      'pendente',
    );
    await repo.registrarPagamento(id, 10, 'pix');
    expect(
      (await _cliente360(
        db,
      ).carregar('client-1')).historicoCompras.single['status_central'],
      'parcial',
    );
    await repo.registrarPagamento(id, 30, 'pix');
    expect(
      (await _cliente360(
        db,
      ).carregar('client-1')).historicoCompras.single['status_central'],
      'paga',
    );
  });

  test('40 cancelamento pelo Cliente 360 usa o fluxo seguro compartilhado', () {
    final centralSource = File(
      'lib/screens/comandas_loja_page.dart',
    ).readAsStringSync();
    expect(
      _cliente360Sources(),
      everyElement(contains('VendaCentralDetalhePage(')),
    );
    expect(centralSource, contains('await commands.estornar('));
  });

  test('41 comanda cancelada permanece no histórico da cliente', () async {
    final id = await _finalized(repo, initialPayment: 40);
    await repo.estornar(id, 'Cancelada pelo Cliente 360');
    final history = (await _cliente360(
      db,
    ).carregar('client-1')).historicoCompras;
    expect(history.single['id'], id);
    expect(history.single['status_central'], 'estornada');
  });

  test('42 voltar do detalhe atualiza as duas telas de Cliente 360', () {
    expect(
      _cliente360Sources(),
      everyElement(
        allOf(contains('await Navigator.push('), contains('await _carregar')),
      ),
    );
  });

  test('43 registro legado permanece somente leitura', () async {
    await db.insert('vendas', {
      'id': 'legacy-1',
      'numero': 'LEG-1',
      'comercio_id': 'commerce-1',
      'cliente_id': 'client-1',
      'usuario_id': 'user-1',
      'subtotal': 19.0,
      'desconto': 0.0,
      'total': 19.0,
      'status': 'concluida',
      'criada_em': DateTime.utc(2026, 8, 18).toIso8601String(),
    });
    final legacy = (await _cliente360(
      db,
    ).carregar('client-1')).historicoCompras.single;
    expect(legacy['origem_registro'], 'legado');
    expect(_cliente360Sources(), everyElement(contains("legado ? null")));
  });

  test('44 navegação não cria comanda duplicada', () async {
    final id = await repo.criar(clienteId: 'client-1');
    await _cliente360(db).carregar('client-1');
    await central.detalhe(id, origem: 'comanda');
    expect(await db.query('comandas_loja'), hasLength(1));
  });

  test('45 detalhe do Cliente 360 não cria pagamento duplicado', () async {
    final id = await _finalized(repo, initialPayment: 40);
    await _cliente360(db).carregar('client-1');
    await central.detalhe(id, origem: 'comanda');
    expect(
      await db.query(
        'comanda_loja_pagamentos',
        where: 'comanda_id=?',
        whereArgs: [id],
      ),
      hasLength(1),
    );
  });

  test(
    '46 detalhe do Cliente 360 não cria conta a receber duplicada',
    () async {
      final id = await _finalized(repo, initialPayment: 0);
      await _cliente360(db).carregar('client-1');
      await central.detalhe(id, origem: 'comanda');
      expect(
        await db.query(
          'contas_receber_loja',
          where: 'comanda_id=?',
          whereArgs: [id],
        ),
        hasLength(1),
      );
    },
  );
}

Cliente360Repository _cliente360(Database db) => Cliente360Repository(
  databaseProvider: () async => db,
  comercioId: 'commerce-1',
);

List<String> _cliente360Sources() => [
  File('lib/screens/clientes_360_page.dart').readAsStringSync(),
  File('lib/screens/cliente_detalhes_premium_page.dart').readAsStringSync(),
];

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
    await db.insert('estoque_saldos', {
      'id': '${product.$1}-sale-balance',
      'business_id': 'commerce-1',
      'estoque_id': product.$1,
      'finalidade': 'venda',
      'quantidade_atual': product.$5,
      'quantidade_reservada': 0.0,
      'created_at': now,
      'updated_at': now,
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
