import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studioflow/models/domain/loja.dart';
import 'package:studioflow/models/domain/scanner_product_draft.dart';
import 'package:studioflow/screens/bip_context_card_page.dart';
import 'package:studioflow/services/bip_context_service.dart';

void main() {
  testWidgets('produto proprio consolida estoque e acoes operacionais', (
    tester,
  ) async {
    final service = _FakeBipContextService();
    await tester.pumpWidget(
      MaterialApp(
        home: BipContextCardPage(
          item: _item(BipItemKind.produtoProprio, tipo: 'produto'),
          service: service,
        ),
      ),
    );

    expect(find.text('Estoque atual: 2.0'), findsOneWidget);
    expect(find.text('-1'), findsOneWidget);
    expect(find.text('+1'), findsOneWidget);
    expect(find.text('Vender'), findsOneWidget);
    expect(find.text('Editar'), findsOneWidget);
    expect(find.text('Apenas conferir'), findsOneWidget);
    expect(find.text('Inativar'), findsOneWidget);

    await tester.tap(find.text('+1'));
    await tester.pump();
    expect(service.increments, 1);
    expect(find.text('Estoque atual: 3.0'), findsOneWidget);
    await tester.tap(find.text('-1'));
    await tester.pump();
    expect(service.decrements, 1);
    expect(find.text('Estoque atual: 2.0'), findsOneWidget);
  });

  testWidgets('peca consignada mostra somente acoes do seu contexto', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BipContextCardPage(
          item: _item(BipItemKind.pecaConsignada, tipo: 'peca_unica'),
          service: _FakeBipContextService(),
        ),
      ),
    );

    expect(find.text('Tipo: peça consignada'), findsOneWidget);
    expect(find.text('Vender'), findsOneWidget);
    expect(find.text('Devolver'), findsOneWidget);
    expect(find.text('Ocorrência'), findsOneWidget);
    expect(find.text('Apenas conferir'), findsOneWidget);
    expect(find.text('Editar'), findsOneWidget);
    expect(find.text('-1'), findsNothing);
    expect(find.text('+1'), findsNothing);
    expect(find.text('Inativar'), findsNothing);
  });
}

BipResolvedItem _item(BipItemKind kind, {required String tipo}) {
  final now = DateTime(2026);
  return BipResolvedItem(
    kind: kind,
    draft: const ScannerProductDraft(
      referenciaComercial: ScannerField('COD-1'),
    ),
    product: ProdutoLoja(
      id: 'produto_1',
      comercioId: 'comercio_1',
      nome: 'Produto teste',
      descricao: 'Descrição teste',
      categoria: 'Categoria',
      tipo: tipo,
      tipoProduto: 'venda',
      modalidade: kind == BipItemKind.pecaConsignada
          ? ModalidadeProduto.consignado
          : ModalidadeProduto.proprio,
      custo: 10,
      precoVenda: 20,
      margem: 50,
      quantidadeAtual: 2,
      estoqueMinimo: 0,
      quantidadeSugerida: 0,
      unidade: 'un',
      quantidadeEmbalagem: 1,
      ativo: true,
      criadoEm: now,
      atualizadoEm: now,
    ),
  );
}

class _FakeBipContextService extends BipContextService {
  int increments = 0;
  int decrements = 0;

  @override
  Future<void> increment(BipResolvedItem item) async => increments++;

  @override
  Future<void> decrement(BipResolvedItem item) async => decrements++;

  @override
  Future<void> deactivate(BipResolvedItem item) async {}
}
