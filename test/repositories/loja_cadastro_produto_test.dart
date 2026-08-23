import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_service.dart';
import 'package:studioflow/models/domain/acesso.dart';
import 'package:studioflow/models/domain/loja.dart';
import 'package:studioflow/repositories/loja_repository.dart';
import 'package:studioflow/services/session_controller.dart';

UsuarioAcesso _owner() => UsuarioAcesso(
      id: 'user-1',
      comercioId: 'commerce-1',
      codigoComercio: 'TEST01',
      nomeComercio: 'Studio',
      nomeExibicao: 'Studio',
      nome: 'Dona',
      telefone: '1199',
      emailLogin: 'dona@local',
      funcao: FuncaoUsuario.dono,
      ativo: true,
      permissoes: ModuloPermissao.values.toSet(),
      acoes: AcaoPermissao.values.toSet(),
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SessionController.instance.entrar(_owner());
    final db = await DatabaseService.instance.database;
    await db.execute('PRAGMA foreign_keys = OFF;');
    await db.execute('DELETE FROM estoque_saldos');
    await db.execute('DELETE FROM movimentacoes_estoque');
    await db.execute('DELETE FROM estoque');
    await db.execute('DELETE FROM comercios');
    await db.execute('PRAGMA foreign_keys = ON;');
    
    await db.insert('comercios', {
      'id': 'commerce-1',
      'codigo_acesso': 'TEST01',
      'nome': 'Studio',
      'nome_exibicao': 'Studio',
      'responsavel': 'Dona',
      'telefone': '1199',
      'email': 'dona@local',
      'ativo': 1,
      'criado_em': DateTime.now().toIso8601String(),
      'atualizado_em': DateTime.now().toIso8601String(),
    });
  });

  group('UX Sprint - Cadastro e Regras de Produto', () {
    test('1-6. Salvar produto novo para VENDA gera entrada inicial, custo, preco', () async {
      final repo = LojaRepository();
      
      final produtoVenda = ProdutoLoja(
        id: 'prod-venda-1',
        comercioId: 'commerce-1',
        nome: 'Shampoo Venda',
        categoria: 'Cabelo',
        marca: 'Loreal',
        tipo: 'produto',
        tipoProduto: 'venda',
        modalidade: ModalidadeProduto.proprio,
        custo: 25.0,
        precoVenda: 50.0,
        margem: 50.0,
        quantidadeAtual: 10.0,
        estoqueMinimo: 0,
        quantidadeSugerida: 0,
        unidade: 'un',
        conteudoPorUnidade: 250,
        unidadeConteudo: 'ml',
        quantidadeEmbalagem: 1,
        ativo: true,
        criadoEm: DateTime.now(),
        atualizadoEm: DateTime.now(),
      );

      await repo.salvarProduto(produtoVenda);

      final db = await DatabaseService.instance.database;
      
      final saldos = await db.query('estoque_saldos', where: 'estoque_id = ?', whereArgs: ['prod-venda-1']);
      expect(saldos.length, 1);
      expect(saldos.first['quantidade_atual'], 10.0);

      final movs = await db.query('movimentacoes_estoque', where: 'item_estoque_id = ?', whereArgs: ['prod-venda-1']);
      expect(movs.length, 1, reason: 'Salvar produto novo deve gerar SOMENTE UMA movimentação inicial');
      expect(movs.first['tipo'], 'entradaManual');
      expect(movs.first['quantidade'], 10.0);
      expect(movs.first['quantidade_anterior'], 0.0);
      expect(movs.first['quantidade_posterior'], 10.0);
      expect(movs.first['observacao'] ?? '', anything);
      
      final saved = await repo.buscarProduto('prod-venda-1');
      expect(saved!.custo, 25.0);
      expect(saved.precoVenda, 50.0);
      expect(saved.conteudoPorUnidade, 250.0);
      expect(saved.unidadeConteudo, 'ml');
      expect(saved.marca, 'Loreal');
    });

    test('2-8. Salvar produto USO SALÃO não exige precoVenda, tem quantidade inicial', () async {
      final repo = LojaRepository();
      
      final produtoSalao = ProdutoLoja(
        id: 'prod-salao-1',
        comercioId: 'commerce-1',
        nome: 'Acetona Interna',
        categoria: 'Manicure',
        tipo: 'insumo',
        tipoProduto: 'uso_interno',
        modalidade: ModalidadeProduto.proprio,
        custo: 12.0,
        precoVenda: 0.0,
        margem: 0.0,
        quantidadeAtual: 3.0, 
        estoqueMinimo: 0,
        quantidadeSugerida: 0,
        unidade: 'pote',
        conteudoPorUnidade: 1,
        unidadeConteudo: 'L',
        quantidadeEmbalagem: 1,
        ativo: true,
        criadoEm: DateTime.now(),
        atualizadoEm: DateTime.now(),
      );

      await repo.salvarProduto(produtoSalao);

      final db = await DatabaseService.instance.database;
      final saldos = await db.query('estoque_saldos', where: 'estoque_id = ?', whereArgs: ['prod-salao-1']);
      expect(saldos.length, 1);
      expect(saldos.first['quantidade_atual'], 3.0);
      
      final movs = await db.query('movimentacoes_estoque', where: 'item_estoque_id = ?', whereArgs: ['prod-salao-1']);
      expect(movs.length, 1);
      expect(movs.first['quantidade'], 3.0);
      
      final rawProduto = await db.query('estoque', where: 'id = ?', whereArgs: ['prod-salao-1']);
      expect(rawProduto.first['tipo_produto'], 'uso_interno');
      expect(rawProduto.first['preco_venda'], 0.0);
      expect(rawProduto.first['unidade_conteudo'], 'L');
    });

    test('19. Editar produto não recria movimentação inicial', () async {
      final repo = LojaRepository();
      
      final produto = ProdutoLoja(
        id: 'prod-edita-1',
        comercioId: 'commerce-1',
        nome: 'Original',
        categoria: 'Geral',
        tipo: 'produto',
        tipoProduto: 'venda',
        modalidade: ModalidadeProduto.proprio,
        custo: 10.0,
        precoVenda: 20.0,
        margem: 50.0,
        quantidadeAtual: 5.0, 
        estoqueMinimo: 0,
        quantidadeSugerida: 0,
        unidade: 'un',
        quantidadeEmbalagem: 1,
        ativo: true,
        criadoEm: DateTime.now(),
        atualizadoEm: DateTime.now(),
      );

      await repo.salvarProduto(produto);
      
      final editado = ProdutoLoja(
        id: 'prod-edita-1',
        comercioId: 'commerce-1',
        nome: 'Alterado',
        categoria: 'Geral',
        tipo: 'produto',
        tipoProduto: 'venda',
        modalidade: ModalidadeProduto.proprio,
        custo: 10.0,
        precoVenda: 20.0,
        margem: 50.0,
        quantidadeAtual: 5.0, // UI envia o que ja tinha
        estoqueMinimo: 0,
        quantidadeSugerida: 0,
        unidade: 'un',
        quantidadeEmbalagem: 1,
        ativo: true,
        criadoEm: DateTime.now(),
        atualizadoEm: DateTime.now(),
      );

      await repo.salvarProduto(editado);
      
      final db = await DatabaseService.instance.database;
      final saldos = await db.query('estoque_saldos', where: 'estoque_id = ?', whereArgs: ['prod-edita-1']);
      expect(saldos.first['quantidade_atual'], 5.0);
      
      final movs = await db.query('movimentacoes_estoque', where: 'item_estoque_id = ?', whereArgs: ['prod-edita-1']);
      expect(movs.length, 1, reason: 'Não deve criar nova movimentação ao editar');
    });

    test('30. Excluir produto na UI vira inativação (ativo=false)', () async {
      final repo = LojaRepository();
      
      final p = ProdutoLoja(
        id: 'prod-exclui-1',
        comercioId: 'commerce-1',
        nome: 'Produto',
        categoria: 'Geral',
        tipo: 'produto',
        tipoProduto: 'venda',
        modalidade: ModalidadeProduto.proprio,
        custo: 10.0,
        precoVenda: 20.0,
        margem: 50.0,
        quantidadeAtual: 5.0, 
        estoqueMinimo: 0,
        quantidadeSugerida: 0,
        unidade: 'un',
        quantidadeEmbalagem: 1,
        ativo: true, 
        criadoEm: DateTime.now(),
        atualizadoEm: DateTime.now(),
      );

      await repo.salvarProduto(p);
      
      // UI simula a inativação
      final pInativo = ProdutoLoja(
        id: 'prod-exclui-1',
        comercioId: p.comercioId,
        nome: p.nome,
        categoria: p.categoria,
        tipo: p.tipo,
        tipoProduto: p.tipoProduto,
        modalidade: p.modalidade,
        custo: p.custo,
        precoVenda: p.precoVenda,
        margem: p.margem,
        quantidadeAtual: p.quantidadeAtual,
        estoqueMinimo: p.estoqueMinimo,
        quantidadeSugerida: p.quantidadeSugerida,
        unidade: p.unidade,
        quantidadeEmbalagem: p.quantidadeEmbalagem,
        ativo: false,
        criadoEm: p.criadoEm,
        atualizadoEm: DateTime.now(),
      );
      
      await repo.salvarProduto(pInativo);
      
      final saved = await repo.buscarProduto('prod-exclui-1');
      expect(saved!.ativo, false, reason: 'Produto deve ser marcado como inativo logicamente');
    });
  });
}
