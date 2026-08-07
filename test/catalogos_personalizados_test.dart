import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/models/domain/acesso.dart';
import 'package:studioflow/models/domain/catalogo_loja.dart';
import 'package:studioflow/repositories/catalogo_loja_repository.dart';
import 'package:studioflow/repositories/comanda_loja_repository.dart';
import 'package:studioflow/services/session_controller.dart';
import 'package:studioflow/widgets/context_action_menu.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late CatalogoLojaRepository catalogos;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 26,
        onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
        onCreate: DatabaseSchemaLatest.criar,
      ),
    );
    SessionController.instance.entrar(_owner());
    final now = DateTime.utc(2026, 8, 3).toIso8601String();
    await db.insert('comercios', {
      'id': 'commerce-1',
      'codigo_acesso': 'CAT01',
      'nome': 'Studio',
      'nome_exibicao': 'Studio',
      'responsavel': 'Dona',
      'telefone': '1199',
      'email': 'dona@local',
      'ativo': 1,
      'criado_em': now,
      'atualizado_em': now,
    });
    await db.insert('unidades', {
      'id': 'unit-1',
      'comercio_id': 'commerce-1',
      'nome': 'Centro',
      'codigo': 'CENTRO',
      'principal': 1,
      'ativo': 1,
      'criado_em': now,
      'atualizado_em': now,
    });
    await db.insert('clientes', {
      'id': 'client-1',
      'nome': 'Cliente',
      'whatsapp': '11999999999',
      'total_gasto': 0,
      'total_atendimentos': 0,
      'observacoes': '',
      'data_cadastro': now,
      'comercio_id': 'commerce-1',
      'ativo': 1,
    });
    SessionController.instance.setUnidadeAtiva('unit-1');
    catalogos = CatalogoLojaRepository(databaseProvider: () async => db);
  });

  tearDown(() async => db.close());

  test('cria, edita, ordena, inativa e exclui catálogo vazio', () async {
    final id = await catalogos.criar(
      nome: 'Cafeteria',
      tipoControle: TipoControleCatalogo.comidas,
    );
    var catalogo = (await catalogos.listar()).single;
    expect(catalogo.nome, 'Cafeteria');
    await catalogos.editar(catalogo.copiarCom(nome: 'Café', ordem: 3));
    await catalogos.alterarStatus(id, false);
    catalogo = (await catalogos.listar()).single;
    expect((catalogo.nome, catalogo.ordem, catalogo.ativo), ('Café', 3, false));
    await catalogos.excluir(id);
    expect(await catalogos.listar(), isEmpty);
  });

  test('produtos dinâmicos, duplicação e proteção do histórico', () async {
    final catalogoId = await catalogos.criar(
      nome: 'Bebidas',
      tipoControle: TipoControleCatalogo.comidas,
    );
    final produtoId = await catalogos.adicionarProduto(
      catalogoId: catalogoId,
      nome: 'Suco',
      codigo: '789001',
      custo: 2,
      preco: 5,
      quantidade: 3,
      estoqueMinimo: 2,
      lote: 'L1',
      validade: DateTime.utc(2026, 12, 1),
    );
    final produto = (await catalogos.produtos(catalogoId)).single;
    expect(produto['data_validade'], contains('2026-12-01'));
    await catalogos.editarProduto(produtoId, {'preco_venda': 6.0});
    final copia = await catalogos.duplicarProduto(produtoId);
    await catalogos.alterarStatusProduto(copia, false);
    await catalogos.excluirProduto(copia);
    await expectLater(catalogos.excluirProduto(produtoId), throwsStateError);
    await expectLater(catalogos.excluir(catalogoId), throwsStateError);
  });

  test('item individual pode ser criado sem código (Fase 3 relaxou a regra)', () async {
    final id = await catalogos.criar(
      nome: 'Joias',
      tipoControle: TipoControleCatalogo.outros,
    );
    // Criação de produto sem código não lança mais erro na arquitetura atual
    final pId = await catalogos.adicionarProduto(
      catalogoId: id,
      nome: 'Anel',
      custo: 10,
      preco: 30,
      quantidade: 1,
      estoqueMinimo: 0,
    );
    expect(pId, isNotEmpty);
    
    await catalogos.adicionarProduto(
      catalogoId: id,
      nome: 'Pulseira',
      codigo: 'PULS-001',
      custo: 10,
      preco: 30,
      quantidade: 1,
      estoqueMinimo: 0,
      lote: 'Maleta 8',
    );
  });

  test('uma comanda combina produtos de catálogos diferentes', () async {
    final bebidas = await catalogos.criar(
      nome: 'Bebidas',
      tipoControle: TipoControleCatalogo.comidas,
    );
    final joias = await catalogos.criar(
      nome: 'Joias',
      tipoControle: TipoControleCatalogo.outros,
    );
    final coca = await catalogos.adicionarProduto(
      catalogoId: bebidas,
      nome: 'Coca-Cola',
      codigo: 'COCA',
      custo: 2,
      preco: 5,
      quantidade: 5,
      estoqueMinimo: 1,
    );
    final brinco = await catalogos.adicionarProduto(
      catalogoId: joias,
      nome: 'Brinco',
      codigo: 'BRINCO',
      custo: 10,
      preco: 25,
      quantidade: 2,
      estoqueMinimo: 0,
    );
    final comandas = ComandaLojaRepository(databaseProvider: () async => db);
    final comanda = await comandas.criar(
      clienteId: 'client-1',
      unidadeId: 'unit-1',
    );
    await comandas.adicionarProduto(comanda, coca, quantidade: 2);
    await comandas.adicionarProduto(comanda, brinco);
    final row = (await db.query(
      'comandas_loja',
      where: 'id = ?',
      whereArgs: [comanda],
    )).single;
    expect(row['total'], 35.0);
    expect(await db.query('comanda_loja_itens'), hasLength(2));
  });

  testWidgets('menu contextual reutiliza ações no botão e pressão longa', (
    tester,
  ) async {
    var count = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContextActionTile(
            semanticLabel: 'Produto',
            title: const Text('Produto'),
            actions: [
              ContextMenuAction(
                id: 'edit',
                label: 'Editar',
                icon: Icons.edit,
                onSelected: () async => count++,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.longPress(find.byType(ContextActionMenu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();
    expect(count, 1);
    await tester.tap(find.byTooltip('Mais ações'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar'));
    expect(count, 2);
  });
}

UsuarioAcesso _owner() => UsuarioAcesso(
  id: 'user-1',
  comercioId: 'commerce-1',
  codigoComercio: 'CAT01',
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
