import '../models/domain/loja.dart';
import '../models/domain/scanner_product_draft.dart';
import '../repositories/loja_repository.dart';

enum BipItemKind { produtoProprio, pecaConsignada, desconhecido }

class BipResolvedItem {
  final BipItemKind kind;
  final ProdutoLoja? product;
  final ScannerProductDraft draft;

  const BipResolvedItem({
    required this.kind,
    required this.draft,
    this.product,
  });
}

class BipContextService {
  final LojaRepository repository;

  BipContextService({LojaRepository? repository})
    : repository = repository ?? LojaRepository();

  Future<BipResolvedItem> resolve(ScannerProductDraft draft) async {
    final code = draft.gtin?.value ?? draft.referenciaComercial?.value;
    if (code == null || code.trim().isEmpty) {
      return BipResolvedItem(kind: BipItemKind.desconhecido, draft: draft);
    }
    final product = await repository.buscarCodigo(code);
    if (product == null) {
      return BipResolvedItem(kind: BipItemKind.desconhecido, draft: draft);
    }
    return BipResolvedItem(
      kind: product.tipo == 'peca_unica'
          ? BipItemKind.pecaConsignada
          : BipItemKind.produtoProprio,
      product: product,
      draft: draft,
    );
  }

  Future<void> increment(BipResolvedItem item) => _move(item, true);
  Future<void> decrement(BipResolvedItem item) => _move(item, false);

  Future<void> _move(BipResolvedItem item, bool incoming) async {
    if (item.kind != BipItemKind.produtoProprio || item.product == null) {
      throw StateError('Ação exclusiva de produto próprio.');
    }
    await repository.movimentar(
      produtoId: item.product!.id,
      tipo: incoming
          ? TipoMovimentoLoja.entradaManual
          : TipoMovimentoLoja.saidaManual,
      quantidade: 1,
      origem: 'modo_bip',
      observacao: incoming ? 'Entrada por Bip' : 'Saída por Bip',
    );
  }

  Future<void> deactivate(BipResolvedItem item) async {
    if (item.kind != BipItemKind.produtoProprio || item.product == null) {
      throw StateError('Peça consignada não pode ser inativada como estoque.');
    }
    await repository.alterarStatusProduto(item.product!.id, false);
  }
}
