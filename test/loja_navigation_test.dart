import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studioflow/screens/loja_areas_page.dart';
import 'package:studioflow/screens/loja_salao_page.dart';

void main() {
  testWidgets('home da Loja mostra exatamente quatro decisões principais', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LojaSalaoPage()));
    expect(find.byKey(const Key('loja_area_vender')), findsOneWidget);
    expect(find.byKey(const Key('loja_area_produtos')), findsOneWidget);
    expect(find.byKey(const Key('loja_area_vendas')), findsOneWidget);
    expect(find.byKey(const Key('loja_area_estoque')), findsOneWidget);
    expect(find.byType(Card), findsNWidgets(4));
  });

  testWidgets('área Produtos preserva pesquisa, adição e catálogos', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ProdutosAreaPage()));
    expect(find.text('Pesquisar produtos'), findsOneWidget);
    expect(find.text('Adicionar produto'), findsOneWidget);
    expect(find.text('Categorias / Catálogos'), findsOneWidget);
    await tester.tap(find.text('Adicionar produto'));
    await tester.pumpAndSettle();
    expect(find.text('Escanear produto'), findsOneWidget);
    expect(find.text('Importar produtos'), findsOneWidget);
    expect(find.text('Cadastro manual'), findsOneWidget);
  });

  testWidgets('agregadores preservam vendas, estoque e reposição', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: VendasRecebimentosAreaPage()),
    );
    expect(find.text('Comandas'), findsOneWidget);
    expect(find.text('Contas a receber'), findsOneWidget);
    expect(find.text('Histórico de vendas'), findsNothing);
    expect(find.text('Estornos'), findsNothing);

    await tester.pumpWidget(
      const MaterialApp(home: EstoqueReposicaoAreaPage()),
    );
    expect(find.text('Estoque'), findsOneWidget);
    expect(find.text('Consignação'), findsOneWidget);
    expect(find.text('Fornecedores'), findsOneWidget);
    expect(find.text('Compras'), findsOneWidget);
  });
}
