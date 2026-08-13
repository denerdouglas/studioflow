import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/models/domain/acesso.dart';
import 'package:studioflow/models/domain/loja.dart';
import 'package:studioflow/repositories/consignacao_repository.dart';
import 'package:studioflow/repositories/loja_repository.dart';
import 'package:studioflow/services/session_controller.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late ConsignacaoRepository repo;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 38,
        onConfigure: (database) => database.execute('PRAGMA foreign_keys=ON'),
        onCreate: DatabaseSchemaLatest.criar,
      ),
    );
    SessionController.instance.entrar(_owner());
    final now = DateTime.utc(2026, 8, 1).toIso8601String();
    await db.insert('comercios', {
      'id': 'commerce-1',
      'codigo_acesso': 'CONSIG',
      'nome': 'Studio',
      'nome_exibicao': 'Studio',
      'responsavel': 'Dona',
      'telefone': '11999999999',
      'email': 'studio@example.com',
      'ativo': 1,
      'criado_em': now,
      'atualizado_em': now,
    });
    await db.insert('fornecedores', {
      'id': 'supplier-1',
      'comercio_id': 'commerce-1',
      'nome': 'Representante',
      'ativo': 1,
      'criado_em': now,
      'atualizado_em': now,
    });
    await db.insert('clientes', {
      'id': 'client-1',
      'comercio_id': 'commerce-1',
      'nome': 'Cliente',
      'whatsapp': '11999999999',
      'total_gasto': 0,
      'total_atendimentos': 0,
      'data_cadastro': now,
      'ativo': 1,
    });
    repo = ConsignacaoRepository(databaseProvider: () async => db);
  });

  tearDown(() async => db.close());

  test(
    'cabeçalho, datas e quantidade criam peças físicas independentes',
    () async {
      final id = await repo.receberMaleta(
        fornecedorId: 'supplier-1',
        nomeLote: 'Remessa 08/2026',
        contrato: 'CTR-8',
        numeroMostruario: 'MOST-12',
        recebidaEm: DateTime.utc(2026, 8, 2),
        recolhimentoPrevisto: DateTime.utc(2026, 9, 2),
        dataPagamento: DateTime.utc(2026, 9, 5),
        observacoes: 'Conferida manualmente',
        pecas: const [
          {
            'codigo': '516205',
            'categoria': 'Anel',
            'nome': 'Anel prata',
            'quantidade': 3,
            'preco': 62,
            'material': 'Prata',
          },
        ],
      );
      final lot = (await db.query('consignacoes')).single;
      expect(lot['contrato'], 'CTR-8');
      expect(lot['numero_mostruario'], 'MOST-12');
      expect(lot['data_prevista_recolhimento'], contains('2026-09-02'));
      expect(lot['data_pagamento'], contains('2026-09-05'));
      expect(lot['quantidade_recebida'], 3.0);
      expect(lot['valor_total_recebido'], 186.0);
      final pieces = await repo.pecas(id);
      expect(pieces, hasLength(3));
      expect(pieces.map((piece) => piece['id']).toSet(), hasLength(3));
      expect(pieces.map((piece) => piece['codigo_exclusivo']).toSet(), {
        '516205',
      });
      expect(pieces.every((piece) => piece['lote_id'] == id), isTrue);
      expect(await db.query('consignacao_eventos'), hasLength(3));
    },
  );

  test(
    'venda exata é transacional, financeira, com cliente opcional',
    () async {
      final id = await _createLot(repo, 'Remessa A', quantity: 3);
      final pieces = await repo.pecas(id);
      await repo.venderPeca(
        pieces.first['id'] as String,
        clienteId: 'client-1',
        valor: 70,
        formaPagamento: 'pix',
      );
      final after = await repo.pecas(id);
      expect(
        after.where((piece) => piece['status'] == 'vendida'),
        hasLength(1),
      );
      expect(
        after.where((piece) => piece['status'] == 'disponivel'),
        hasLength(2),
      );
      expect(
        after.firstWhere((piece) => piece['status'] == 'vendida')['cliente_id'],
        'client-1',
      );
      expect(await db.query('pdv_vendas'), hasLength(1));
      expect(
        (await db.query('movimentacoes_financeiras')).single['valor'],
        70.0,
      );
      final event = (await db.query(
        'consignacao_eventos',
        where: "tipo='venda'",
      )).single;
      expect(event['venda_id'], isNotNull);
      expect(event['cliente_id'], 'client-1');
      await expectLater(
        repo.venderPeca(pieces.first['id'] as String),
        throwsStateError,
      );

      await repo.venderPeca(
        pieces[1]['id'] as String,
        formaPagamento: 'dinheiro',
      );
      final anonymousSale = (await db.query(
        'pdv_vendas',
        orderBy: 'data_venda DESC',
        limit: 1,
      )).single;
      expect(anonymousSale['cliente_id'], isNull);
    },
  );

  test('filtros, busca, totais e legado NULL são defensivos', () async {
    final id = await _createLot(repo, 'Remessa filtros', quantity: 3);
    final pieces = await repo.pecas(id);
    await repo.venderPeca(pieces[0]['id'] as String);
    await repo.devolverPeca(pieces[1]['id'] as String);
    expect(await repo.pecas(id, status: 'disponivel'), hasLength(1));
    expect(await repo.pecas(id, status: 'vendida'), hasLength(1));
    expect(await repo.pecas(id, status: 'devolvida'), hasLength(1));
    expect(await repo.pecas(id, pesquisa: '516205'), hasLength(3));
    expect(await repo.pecas(id, pesquisa: 'anel'), hasLength(3));
    final detail = await repo.detalhe(id);
    expect(detail['quantidade_real'], 3);
    expect(detail['vendidas_real'], 1);
    expect(detail['devolvidas_real'], 1);
    await db.update(
      'pecas_unicas',
      {'categoria': null, 'descricao': null, 'observacoes': null},
      where: 'lote_id=?',
      whereArgs: [id],
    );
    expect((await repo.detalhe(id))['quantidade_real'], 3);
  });

  test('comanda de três peças cria uma venda e três itens', () async {
    final id = await _createLot(repo, 'Comanda múltipla', quantity: 3);
    final pieces = await repo.pecas(id);
    final saleId = await repo.venderPecas(
      pieces.map((piece) => piece['id'] as String),
      clienteId: 'client-1',
      formaPagamento: 'pix',
      dataVenda: DateTime.utc(2026, 8, 12),
      dataPagamento: DateTime.utc(2026, 8, 20),
    );
    expect(await db.query('pdv_vendas'), hasLength(1));
    expect(
      await db.query(
        'pdv_venda_itens',
        where: 'pdv_venda_id=?',
        whereArgs: [saleId],
      ),
      hasLength(3),
    );
    expect((await db.query('pdv_vendas')).single['valor_total'], 186.0);
    expect(
      (await db.query('movimentacoes_financeiras')).single['valor'],
      186.0,
    );
    expect(await repo.pecas(id, status: 'vendida'), hasLength(3));
  });

  test('falha em uma peça reverte toda a comanda', () async {
    final id = await _createLot(repo, 'Comanda atômica', quantity: 2);
    final pieces = await repo.pecas(id);
    await repo.venderPeca(pieces.first['id'] as String);
    await expectLater(
      repo.venderPecas(
        pieces.map((piece) => piece['id'] as String),
        clienteId: 'client-1',
      ),
      throwsStateError,
    );
    expect(await db.query('pdv_vendas'), hasLength(1));
    expect(await db.query('pdv_venda_itens'), hasLength(1));
  });

  test(
    'venda mista cria uma venda para produto próprio e peça consignada',
    () async {
      final now = DateTime.utc(2026, 8, 12).toIso8601String();
      await db.insert('estoque', {
        'id': 'own-product',
        'comercio_id': 'commerce-1',
        'estoque_destino': 'loja',
        'nome': 'Shampoo',
        'categoria': 'Cabelo',
        'tipo': 'produto',
        'tipo_produto': 'venda',
        'modalidade': 'proprio',
        'custo_unitario': 30.0,
        'preco_venda': 60.0,
        'margem': 30.0,
        'quantidade_atual': 2.0,
        'estoque_minimo': 0.0,
        'quantidade_sugerida': 0.0,
        'unidade': 'un',
        'quantidade_embalagem': 1.0,
        'ativo': 1,
        'data_cadastro': now,
        'atualizado_em': now,
      });
      await db.insert('estoque_saldos', {
        'id': 'own-product-sale-balance',
        'business_id': 'commerce-1',
        'estoque_id': 'own-product',
        'finalidade': 'venda',
        'quantidade_atual': 2.0,
        'quantidade_reservada': 0.0,
        'estoque_minimo': 0.0,
        'created_at': now,
        'updated_at': now,
      });
      final lotId = await _createLot(repo, 'Venda mista', quantity: 1);
      final loja = LojaRepository(databaseProvider: () async => db);
      final available = await loja.listarItensParaVenda();
      final own = available.singleWhere((item) => item.id == 'own-product');
      final piece = available.singleWhere((item) => item.tipo == 'peca_unica');
      final saleId = await loja.finalizarVenda(
        itens: [ItemCarrinho(own, 1), ItemCarrinho(piece, 1)],
        desconto: 0,
        pagamentos: const {'pix': 122},
        profissionalId: 'user-1',
        clienteId: 'client-1',
      );
      expect(await db.query('pdv_vendas'), hasLength(1));
      expect(
        await db.query(
          'pdv_venda_itens',
          where: 'pdv_venda_id=?',
          whereArgs: [saleId],
        ),
        hasLength(2),
      );
      expect((await db.query('pdv_vendas')).single['valor_total'], 122.0);
      expect((await loja.buscarProduto('own-product'))!.quantidadeAtual, 1.0);
      expect((await repo.pecas(lotId)).single['status'], 'vendida');
    },
  );

  test(
    'estorno preserva venda e histórico, devolvendo peça e financeiro',
    () async {
      final id = await _createLot(repo, 'Estorno', quantity: 1);
      final piece = (await repo.pecas(id)).single;
      await repo.venderPeca(piece['id'] as String, clienteId: 'client-1');
      await repo.estornarVendaDaPeca(piece['id'] as String, 'Cliente devolveu');
      expect((await db.query('pdv_vendas')).single['status'], 'estornada');
      expect((await repo.pecas(id)).single['status'], 'disponivel');
      expect(
        await db.query('consignacao_eventos', where: "tipo='estorno_venda'"),
        hasLength(1),
      );
      expect(await db.query('movimentacoes_financeiras'), hasLength(2));
    },
  );

  test('fechamento preserva peças/eventos e remessas são isoladas', () async {
    final first = await _createLot(repo, 'Remessa 07', quantity: 2);
    final second = await _createLot(repo, 'Remessa 08', quantity: 2);
    final firstPieces = await repo.pecas(first);
    await repo.venderPeca(firstPieces.first['id'] as String);
    await repo.fecharRemessa(
      first,
      pecasDevolvidas: [firstPieces.last['id'] as String],
    );
    expect((await repo.detalhe(first))['status'], 'fechada');
    expect(await repo.pecas(first), hasLength(2));
    expect(await repo.pecas(second), hasLength(2));
    expect(
      (await repo.pecas(
        first,
      )).where((piece) => piece['status'] == 'devolvida'),
      hasLength(1),
    );
    expect(
      await db.query(
        'consignacao_eventos',
        where: 'consignacao_id=?',
        whereArgs: [first],
      ),
      hasLength(4),
    );
  });

  test('200+ peças usam consulta limitada e sem N+1', () async {
    final id = await _createLot(repo, 'Remessa grande', quantity: 250);
    expect(await repo.pecas(id), hasLength(250));
    expect(await repo.pecas(id, limit: 50), hasLength(50));
    expect((await repo.detalhe(id))['quantidade_real'], 250);
  });
}

Future<String> _createLot(
  ConsignacaoRepository repo,
  String name, {
  required int quantity,
}) => repo.receberMaleta(
  fornecedorId: 'supplier-1',
  nomeLote: name,
  pecas: [
    {
      'codigo': '516205',
      'categoria': 'Anel',
      'nome': 'Anel prata',
      'descricao': 'Anel prata',
      'quantidade': quantity,
      'preco': 62.0,
    },
  ],
);

UsuarioAcesso _owner() => UsuarioAcesso(
  id: 'user-1',
  comercioId: 'commerce-1',
  codigoComercio: 'CONSIG',
  nomeComercio: 'Studio',
  nomeExibicao: 'Studio',
  nome: 'Dona',
  telefone: '11999999999',
  emailLogin: 'studio@example.com',
  funcao: FuncaoUsuario.dono,
  ativo: true,
  permissoes: ModuloPermissao.values.toSet(),
  acoes: AcaoPermissao.values.toSet(),
);
