import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_schema.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/database/migrations/migration_v2_impl.dart';
import 'package:studioflow/database/migrations/migration_v2_triggers.dart';
import 'package:studioflow/integrations/marketplace_provider.dart';
import 'package:studioflow/models/domain/acesso.dart';
import 'package:studioflow/models/domain/loja.dart';
import 'package:studioflow/repositories/acesso_repository.dart';
import 'package:studioflow/repositories/compras_repository.dart';
import 'package:studioflow/repositories/consignacao_repository.dart';
import 'package:studioflow/repositories/loja_repository.dart';
import 'package:studioflow/repositories/produto_fornecedor_repository.dart';
import 'package:studioflow/services/session_controller.dart';

void main() {
  sqfliteFfiInit();

  group('Sprint 3 - migração e loja', () {
    late Database db;
    late AcessoRepository acesso;
    late LojaRepository loja;
    late UsuarioAcesso dono;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 3,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: DatabaseSchemaLatest.criar,
        ),
      );
      acesso = AcessoRepository(databaseProvider: () async => db);
      dono = await acesso.cadastrarComercio(
        const CadastroComercioEntrada(
          nomeComercio: 'Salão Sprint 3',
          nomeExibicao: 'Sprint 3',
          responsavel: 'Pessoa Dona',
          telefone: '11999999999',
          email: 'dono@sprint3.test',
          senha: 'Senha@123',
          permanecerConectado: false,
        ),
      );
      SessionController.instance.entrar(dono);
      loja = LojaRepository(databaseProvider: () async => db);
    });

    tearDown(() async {
      await db.close();
    });

    test('migração v2 para v3 preserva estoque e cria backup', () async {
      await db.close();
      final caminho = join(
        Directory.systemTemp.path,
        'studioflow_sprint3_migration.db',
      );
      await databaseFactoryFfi.deleteDatabase(caminho);
      addTearDown(() => databaseFactoryFfi.deleteDatabase(caminho));
      db = await databaseFactoryFfi.openDatabase(
        caminho,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, _) async {
            await DatabaseSchema.criar(db, 1);
            await MigrationV2.executar(db, criarBackup: false);
            await MigrationV2Triggers.executar(db);
          },
        ),
      );
      await db.insert('estoque', {
        'id': 'legado_estoque',
        'nome': 'Produto preservado',
        'categoria': 'Cosmético',
        'tipo': 'produto',
        'quantidade_atual': 7,
        'estoque_minimo': 2,
        'unidade': 'un',
        'custo_unitario': 10,
        'data_cadastro': DateTime(2026).toIso8601String(),
      });
      await db.close();
      db = await databaseFactoryFfi.openDatabase(
        caminho,
        options: OpenDatabaseOptions(
          version: 3,
          onUpgrade: DatabaseSchemaLatest.migrar,
        ),
      );
      final estoque = await db.query(
        'estoque',
        where: 'id = ?',
        whereArgs: ['legado_estoque'],
      );
      final backup = await db.query(
        'backups_logicos',
        where: 'versao_origem = ? AND tabela = ?',
        whereArgs: [2, 'estoque'],
      );
      expect(estoque.single['nome'], 'Produto preservado');
      expect(estoque.single['modalidade'], 'proprio');
      expect(backup, isNotEmpty);
    });

    test(
      'produto, movimento e alerta de reposição são transacionais',
      () async {
        final produto = _produto(
          dono,
          id: 'produto_1',
          quantidade: 3,
          minimo: 5,
        );
        await loja.salvarProduto(produto);

        final salvo = await loja.buscarProduto(produto.id);
        final historico = await loja.historico(produto.id);
        final reposicoes = await loja.listarReposicoes();
        expect(salvo!.quantidadeAtual, 3);
        expect(historico.single['tipo'], TipoMovimentoLoja.entradaManual.name);
        expect(reposicoes.single['produto_id'], produto.id);

        await expectLater(
          loja.movimentar(
            produtoId: produto.id,
            tipo: TipoMovimentoLoja.perda,
            quantidade: 4,
            origem: 'teste',
          ),
          throwsStateError,
        );
        expect((await loja.buscarProduto(produto.id))!.quantidadeAtual, 3);
      },
    );

    test('venda baixa estoque e cancelamento autorizado estorna', () async {
      final produto = _produto(
        dono,
        id: 'produto_venda',
        quantidade: 10,
        minimo: 2,
      );
      await loja.salvarProduto(produto);
      final vendaId = await loja.finalizarVenda(
        itens: [ItemCarrinho((await loja.buscarProduto(produto.id))!, 2)],
        desconto: 5,
        pagamentos: const {'pix': 20, 'cartao': 15},
        profissionalId: 'prof_1',
      );
      expect((await loja.buscarProduto(produto.id))!.quantidadeAtual, 8);
      final pagamentos = await db.query(
        'movimentacoes_financeiras',
        where: "id LIKE ?",
        whereArgs: ['${vendaId}_p%'],
      );
      expect(pagamentos, hasLength(2));
      await loja.cancelarVenda(vendaId, 'Cancelamento de teste');
      expect((await loja.buscarProduto(produto.id))!.quantidadeAtual, 10);
      final movimentos = await loja.historico(produto.id);
      expect(
        movimentos.map((m) => m['tipo']),
        containsAll(['venda', 'cancelamentoVenda']),
      );
    });

    test('consignação calcula fechamento usando vendas reais', () async {
      final produto = _produto(
        dono,
        id: 'produto_consignado',
        quantidade: 0,
        minimo: 0,
      );
      await loja.salvarProduto(produto);
      final fornecedor = _fornecedor(dono, 'fornecedor_consignado');
      await loja.salvarFornecedor(fornecedor);
      final consignacao = ConsignacaoRepository(
        databaseProvider: () async => db,
      );
      final id = await consignacao.receber(
        fornecedorId: fornecedor.id,
        produtoId: produto.id,
        quantidade: 5,
        repasse: 12,
        precoVenda: 20,
        percentualSalao: 40,
      );
      final atualizado = (await loja.buscarProduto(produto.id))!;
      await loja.finalizarVenda(
        itens: [ItemCarrinho(atualizado, 2)],
        desconto: 0,
        pagamentos: const {'dinheiro': 40},
        profissionalId: 'prof_1',
      );
      final resumo = await consignacao.resumo(id);
      expect(resumo.recebidos, 5);
      expect(resumo.vendidos, 2);
      expect(resumo.faturamento, 40);
      expect(resumo.valorFornecedor, 24);
      expect(resumo.valorSalao, 16);
      await consignacao.fechar(id);
      expect((await loja.buscarProduto(produto.id))!.quantidadeAtual, 0);
      final fechado = await consignacao.resumo(id);
      expect(fechado.devolvidos, 3);
    });

    test(
      'ordem exige aprovação e recebimento parcial atualiza estoque',
      () async {
        final produto = _produto(
          dono,
          id: 'produto_ordem',
          quantidade: 1,
          minimo: 3,
        );
        await loja.salvarProduto(produto);
        final compras = ComprasRepository(databaseProvider: () async => db);
        final ordemId = await compras.criarOrdem(
          itens: [ItemOrdemEntrada(produto, 4, 10)],
        );
        await compras.aprovar(ordemId);
        final itens = await compras.itensOrdem(ordemId);
        await compras.receber(ordemId, {itens.single['id'] as String: 2});
        expect((await loja.buscarProduto(produto.id))!.quantidadeAtual, 3);
        final ordens = await compras.listarOrdens();
        expect(ordens.single['status'], 'recebido_parcialmente');
        final reposicoes = await loja.listarReposicoes();
        expect(reposicoes.single['status'], 'recebido_parcialmente');
      },
    );

    test('produto aceita vários fornecedores com condições reais', () async {
      final produto = _produto(
        dono,
        id: 'produto_fornecedor',
        quantidade: 2,
        minimo: 1,
      );
      await loja.salvarProduto(produto);
      final f1 = _fornecedor(dono, 'fornecedor_1');
      final f2 = _fornecedor(dono, 'fornecedor_2');
      await loja.salvarFornecedor(f1);
      await loja.salvarFornecedor(f2);
      final vinculos = ProdutoFornecedorRepository(
        databaseProvider: () async => db,
      );
      await vinculos.salvar(
        produtoId: produto.id,
        fornecedorId: f1.id,
        preco: 10,
        quantidadeEmbalagem: 1,
        prazoDias: 2,
      );
      await vinculos.salvar(
        produtoId: produto.id,
        fornecedorId: f2.id,
        preco: 18,
        quantidadeEmbalagem: 2,
        prazoDias: 1,
      );
      final salvos = await vinculos.listar(produtoId: produto.id);
      expect(salvos, hasLength(2));
      expect(salvos.first['fornecedor_nome'], contains('fornecedor_1'));
    });
    test('dados de dois comércios permanecem isolados', () async {
      await loja.salvarProduto(
        _produto(dono, id: 'produto_empresa_a', quantidade: 1, minimo: 0),
      );
      final outro = await acesso.cadastrarComercio(
        const CadastroComercioEntrada(
          nomeComercio: 'Outro Salão',
          nomeExibicao: 'Outro',
          responsavel: 'Outra Pessoa',
          telefone: '11888888888',
          email: 'dono@outro.test',
          senha: 'Senha@456',
          permanecerConectado: false,
        ),
      );
      SessionController.instance.entrar(outro);
      await loja.salvarProduto(
        _produto(outro, id: 'produto_empresa_b', quantidade: 2, minimo: 0),
      );
      expect((await loja.listarProdutos()).map((p) => p.id), [
        'produto_empresa_b',
      ]);
      SessionController.instance.entrar(dono);
      expect((await loja.listarProdutos()).map((p) => p.id), [
        'produto_empresa_a',
      ]);
    });

    test(
      'providers externos geram links oficiais sem resultados falsos',
      () async {
        final ml = MercadoLivreProvider();
        final shopee = ShopeeProvider();
        expect(
          ml.uriPesquisa('shampoo profissional').host,
          'lista.mercadolivre.com.br',
        );
        expect(
          shopee.uriPesquisa('shampoo profissional').host,
          'shopee.com.br',
        );
        expect(await ml.pesquisar('teste'), isEmpty);
        expect(await shopee.pesquisar('teste'), isEmpty);
      },
    );
  });
}

ProdutoLoja _produto(
  UsuarioAcesso dono, {
  required String id,
  required double quantidade,
  required double minimo,
}) {
  final agora = DateTime(2026, 7, 22);
  return ProdutoLoja(
    id: id,
    comercioId: dono.comercioId,
    nome: 'Produto $id',
    tipoProduto: 'venda',
    categoria: 'Cosméticos',
    tipo: 'produto',
    modalidade: ModalidadeProduto.proprio,
    custo: 10,
    precoVenda: 20,
    margem: 50,
    quantidadeAtual: quantidade,
    estoqueMinimo: minimo,
    quantidadeSugerida: 0,
    unidade: 'un',
    quantidadeEmbalagem: 1,
    ativo: true,
    criadoEm: agora,
    atualizadoEm: agora,
  );
}

FornecedorLoja _fornecedor(UsuarioAcesso dono, String id) => FornecedorLoja(
  id: id,
  comercioId: dono.comercioId,
  nome: 'Fornecedor $id',
  prazoDias: 3,
  entrega: true,
);

