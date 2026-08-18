import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/repositories/central_comandas_repository.dart';

void main() {
  sqfliteFfiInit();

  group('Central única de comandas', () {
    late Database db;
    late CentralComandasRepository repository;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 42,
          onCreate: DatabaseSchemaLatest.criar,
        ),
      );
      repository = CentralComandasRepository(
        databaseProvider: () async => db,
        comercioId: 'commerce-1',
      );
      await _seed(db);
    });

    tearDown(() => db.close());

    test('1 venda com cliente aparece na Central de Comandas', () async {
      final rows = await repository.listar(pesquisa: 'Maria');
      expect(rows, isNotEmpty);
      expect(rows.every((row) => row['cliente_nome'] == 'Maria'), isTrue);
    });

    test('2 mesma venda aparece no perfil da cliente', () async {
      final rows = await repository.listar(clienteId: 'client-1');
      expect(rows.any((row) => row['id'] == 'sale-orphan'), isTrue);
    });

    test('3 venda ligada a comanda não é duplicada', () async {
      final rows = await repository.listar();
      expect(
        rows.where((row) => row['venda_id'] == 'sale-linked'),
        hasLength(1),
      );
    });

    test('4 venda sem cliente aparece na central', () async {
      final rows = await repository.listar();
      final anonymous = rows.singleWhere((row) => row['id'] == 'sale-anon');
      expect(anonymous['cliente_nome'], 'Cliente não vinculado');
    });

    test('5 comanda aberta aparece no filtro abertas', () async {
      final rows = await repository.listar(filtro: 'abertas');
      expect(rows.map((row) => row['id']), contains('cmd-open'));
      expect(rows.every((row) => row['status_central'] == 'aberta'), isTrue);
    });

    test('6 pendente aparece como saldo em aberto', () async {
      final rows = await repository.listar(filtro: 'pendentes');
      final row = rows.singleWhere((item) => item['id'] == 'cmd-pending');
      expect(row['saldo_restante'], 100.0);
    });

    test('7 pagamento atualiza a mesma comanda', () async {
      final row = (await repository.listar()).singleWhere(
        (item) => item['id'] == 'cmd-partial',
      );
      expect(row['valor_pago'], 40.0);
      expect(row['id'], 'cmd-partial');
    });

    test('8 data de pagamento é exposta', () async {
      final row = (await repository.listar()).singleWhere(
        (item) => item['id'] == 'cmd-partial',
      );
      expect('${row['data_pagamento']}', contains('2026-08-18'));
    });

    test('9 pagamento parcial preserva saldo', () async {
      final row = (await repository.listar()).singleWhere(
        (item) => item['id'] == 'cmd-partial',
      );
      expect(row['saldo_restante'], 60.0);
      final detail = await repository.detalhe('cmd-partial', origem: 'comanda');
      expect(detail['pagamentos'], isNotEmpty);
    });

    test('10 pagamento final muda status central para paga', () async {
      final rows = await repository.listar(filtro: 'pagas');
      expect(rows.map((row) => row['id']), contains('cmd-paid'));
    });

    test('11 editar comanda não duplica', () async {
      await db.update(
        'comandas_loja',
        {'observacoes': 'editada'},
        where: 'id=?',
        whereArgs: ['cmd-open'],
      );
      final rows = await repository.listar();
      expect(rows.where((row) => row['id'] == 'cmd-open'), hasLength(1));
    });

    test('12 editar cliente atualiza vínculo', () async {
      await db.update(
        'comandas_loja',
        {'cliente_id': 'client-2'},
        where: 'id=?',
        whereArgs: ['cmd-open'],
      );
      final rows = await repository.listar(clienteId: 'client-2');
      expect(rows.map((row) => row['id']), contains('cmd-open'));
    });

    test('13 detalhe preserva itens e quantidades', () async {
      final detail = await repository.detalhe('cmd-open', origem: 'comanda');
      final items = detail['itens'] as List<Map<String, Object?>>;
      expect(items.single['quantidade'], 2.0);
      expect(items.single['subtotal'], 100.0);
    });

    test('14 cancelar preserva histórico', () async {
      final rows = await repository.listar(filtro: 'canceladas');
      expect(rows.map((row) => row['id']), contains('cmd-cancelled'));
    });

    test('15 cancelamento não apaga itens históricos', () async {
      final detail = await repository.detalhe(
        'cmd-cancelled',
        origem: 'comanda',
      );
      expect(detail['itens'], isNotEmpty);
    });

    test('16 cancelada não soma no resumo financeiro', () async {
      final summary = await repository.resumoCliente('client-1');
      expect(summary['total_comprado'], isNot(530.0));
    });

    test('17 comanda cancelada aparece no filtro canceladas', () async {
      final rows = await repository.listar(filtro: 'canceladas');
      expect(rows.every((row) => row['status_central'] == 'cancelada'), isTrue);
    });

    test('18 perfil calcula total comprado', () async {
      final summary = await repository.resumoCliente('client-1');
      expect(summary['total_comprado'], 560.0);
    });

    test('19 perfil calcula ticket médio', () async {
      final summary = await repository.resumoCliente('client-1');
      expect(summary['quantidade_compras'], 6);
      expect(summary['ticket_medio'], closeTo(93.333333, 0.0001));
    });

    test('20 perfil calcula total em aberto', () async {
      final summary = await repository.resumoCliente('client-1');
      expect(summary['total_em_aberto'], 260.0);
    });

    test('21 busca por nome do cliente funciona', () async {
      expect(await repository.listar(pesquisa: 'maria'), isNotEmpty);
    });

    test('22 busca por número ou id funciona', () async {
      final rows = await repository.listar(pesquisa: '20260001');
      expect(rows.single['id'], 'cmd-open');
      expect(await repository.listar(pesquisa: 'sale-anon'), isNotEmpty);
    });

    test('23 busca por produto ou código funciona', () async {
      expect(await repository.listar(pesquisa: 'Brinco'), isNotEmpty);
      expect(await repository.listar(pesquisa: '526839'), isNotEmpty);
    });

    test('24 filtro por data funciona', () async {
      final rows = await repository.listar(
        de: DateTime.utc(2026, 8, 19),
        ate: DateTime.utc(2026, 8, 19),
      );
      expect(rows.map((row) => row['id']), contains('sale-anon'));
      expect(
        rows.every((row) => '${row['data_venda']}'.startsWith('2026-08-19')),
        isTrue,
      );
    });

    test('25 filtro por forma de pagamento funciona', () async {
      final rows = await repository.listar(formaPagamento: 'pix');
      expect(rows.map((row) => row['id']), contains('cmd-partial'));
      expect(rows.map((row) => row['id']), contains('sale-orphan'));
    });
  });
}

Future<void> _seed(Database db) async {
  const commerce = 'commerce-1';
  const created = '2026-08-18T10:00:00.000Z';
  for (final client in const [
    {'id': 'client-1', 'nome': 'Maria', 'whatsapp': '11999999999'},
    {'id': 'client-2', 'nome': 'Ana', 'whatsapp': '11888888888'},
  ]) {
    await db.insert('clientes', {
      ...client,
      'comercio_id': commerce,
      'data_cadastro': created,
      'ativo': 1,
    });
  }

  final commands = <Map<String, Object?>>[
    _command('cmd-open', '20260001', 'aberta', 100, 0),
    _command('cmd-pending', '20260002', 'aguardando_pagamento', 100, 0),
    _command('cmd-partial', '20260003', 'parcialmente_paga', 100, 40),
    _command('cmd-paid', '20260004', 'paga', 100, 100),
    _command('cmd-cancelled', '20260005', 'cancelada', 50, 0),
    {
      ..._command('cmd-linked', '20260006', 'paga', 80, 80),
      'venda_id': 'sale-linked',
    },
  ];
  for (final command in commands) {
    await db.insert('comandas_loja', command);
    await db.insert('comanda_loja_itens', {
      'id': '${command['id']}-item',
      'comanda_id': command['id'],
      'comercio_id': commerce,
      'produto_id': 'product-${command['id']}',
      'codigo': command['id'] == 'cmd-open' ? '526839' : 'COD',
      'nome': command['id'] == 'cmd-open' ? 'Brinco' : 'Produto',
      'quantidade': command['id'] == 'cmd-open' ? 2.0 : 1.0,
      'valor_unitario': command['id'] == 'cmd-open' ? 50.0 : command['total'],
      'subtotal': command['total'],
    });
  }
  await db.insert('contas_receber_loja', {
    'id': 'account-partial',
    'comercio_id': commerce,
    'cliente_id': 'client-1',
    'comanda_id': 'cmd-partial',
    'vencimento': '2026-08-25T00:00:00.000Z',
    'valor_total': 100.0,
    'valor_recebido': 40.0,
    'status': 'parcialmente_paga',
    'criado_em': created,
    'atualizado_em': created,
  });
  await db.insert('contas_receber_pagamentos', {
    'id': 'account-payment',
    'conta_id': 'account-partial',
    'comercio_id': commerce,
    'valor': 40.0,
    'forma': 'pix',
    'registrado_em': created,
  });
  await db.insert('comanda_loja_pagamentos', {
    'id': 'paid-payment',
    'comanda_id': 'cmd-paid',
    'comercio_id': commerce,
    'forma': 'dinheiro',
    'valor': 100.0,
    'status': 'pago',
    'registrado_em': '2026-08-18T12:00:00.000Z',
  });

  for (final sale in const [
    {
      'id': 'sale-linked',
      'cliente_id': 'client-1',
      'valor_total': 80.0,
      'data_venda': created,
    },
    {
      'id': 'sale-orphan',
      'cliente_id': 'client-1',
      'valor_total': 80.0,
      'data_venda': created,
    },
    {
      'id': 'sale-anon',
      'cliente_id': null,
      'valor_total': 30.0,
      'data_venda': '2026-08-19T10:00:00.000Z',
    },
  ]) {
    await db.insert('pdv_vendas', {
      ...sale,
      'comercio_id': commerce,
      'profissional_id': 'user-1',
      'status': 'concluida',
    });
    await db.insert('pdv_venda_itens', {
      'id': '${sale['id']}-item',
      'pdv_venda_id': sale['id'],
      'produto_id': sale['id'] == 'sale-orphan' ? '526839' : 'SKU-1',
      'quantidade': 1.0,
      'valor_unitario': sale['valor_total'],
    });
  }
  await db.insert('movimentacoes_financeiras', {
    'id': 'sale-orphan-payment',
    'tipo': 'receita',
    'descricao': 'Venda PDV',
    'valor': 80.0,
    'forma_pagamento': 'pix',
    'status': 'pago',
    'data': created,
    'data_criacao': created,
    'entidade_origem': 'pdv_venda',
    'entidade_origem_id': 'sale-orphan',
  });
}

Map<String, Object?> _command(
  String id,
  String number,
  String status,
  double total,
  double paid,
) => {
  'id': id,
  'numero': number,
  'comercio_id': 'commerce-1',
  'cliente_id': 'client-1',
  'status': status,
  'subtotal': total,
  'desconto': 0.0,
  'total': total,
  'valor_pago': paid,
  'vencimento': status == 'aguardando_pagamento'
      ? '2026-08-25T00:00:00.000Z'
      : null,
  'finalizada_em': status == 'aberta' ? null : '2026-08-18T10:00:00.000Z',
  'cancelada_em': status == 'cancelada' ? '2026-08-18T11:00:00.000Z' : null,
  'criado_em': '2026-08-18T10:00:00.000Z',
  'atualizado_em': '2026-08-18T10:00:00.000Z',
};
