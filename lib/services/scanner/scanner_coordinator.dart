import '../../models/domain/scanner_product_draft.dart';
import '../product_lookup_service.dart';

abstract class ScannerProvider {
  Future<ScannerProductDraft?> searchBarcode(String gtin);
  Future<ScannerProductDraft?> analyzeImage(
    String imagePath, {
    bool isFront = true,
  });
}

class ScannerCoordinator {
  final List<ScannerProvider> _externalProviders;
  // Local repository injection would go here (e.g. EstoqueRepository)

  ScannerCoordinator({List<ScannerProvider>? externalProviders})
    : _externalProviders = externalProviders ?? [];

  /// Realiza o fluxo de orquestração:
  /// 1. Tenta buscar no banco local (não implementado no coordinator abstrato, feito na UI/ViewModel)
  /// 2. Se falhar, busca em provedores externos
  Future<ScannerProductDraft?> searchExternalBarcode(String gtin) async {
    for (var provider in _externalProviders) {
      try {
        final draft = await provider.searchBarcode(gtin);
        if (draft != null) return draft;
      } catch (e) {
        // Ignora erro externo e tenta o próximo provedor.
        // A falha externa nunca deve bloquear o usuário.
      }
    }
    // Retorna um draft apenas com o código se não achou nada externo
    return ScannerProductDraft(
      gtin: ScannerField(
        gtin,
        source: 'barcode',
        confidence: ScannerConfidence.baixa,
        reviewReason: 'GTIN válido, mas sem correspondência exata no catálogo.',
      ),
      reviewReasons: const [
        'Produto não encontrado; revise ou cadastre manualmente.',
      ],
    );
  }

  /// Analisa frente e verso (se disponível) para criar um único Draft.
  Future<ScannerProductDraft> analyzeImages(
    String frontPath, {
    String? backPath,
  }) async {
    ScannerProductDraft finalDraft = const ScannerProductDraft();

    // Tenta os provedores para a frente
    for (var provider in _externalProviders) {
      try {
        final frontDraft = await provider.analyzeImage(
          frontPath,
          isFront: true,
        );
        if (frontDraft != null) {
          finalDraft = frontDraft;
          break;
        }
      } catch (_) {}
    }

    // Tenta mesclar com informações do verso se houver
    if (backPath != null) {
      for (var provider in _externalProviders) {
        try {
          final backDraft = await provider.analyzeImage(
            backPath,
            isFront: false,
          );
          if (backDraft != null) {
            // Em uma implementação real profunda, faríamos um merge campo a campo
            // Aqui preservamos o principal da frente e enriquecemos.
            finalDraft = mergeDrafts(finalDraft, backDraft);
            break;
          }
        } catch (_) {}
      }
    }

    // Se nenhum provider resolveu, apenas retorna as imagens para revisão/cadastro manual
    return ScannerProductDraft(
      imagemFrente: frontPath,
      imagemVerso: backPath,
      gtin: finalDraft.gtin,
      qr: finalDraft.qr,
      referenciaComercial: finalDraft.referenciaComercial,
      referenciaInterna: finalDraft.referenciaInterna,
      nome: finalDraft.nome,
      marca: finalDraft.marca,
      descricao: finalDraft.descricao,
      quantidadeEmbalagem: finalDraft.quantidadeEmbalagem,
      unidade: finalDraft.unidade,
      validade: finalDraft.validade,
      lote: finalDraft.lote,
      categoriaSugerida: finalDraft.categoriaSugerida,
      preco: finalDraft.preco,
      material: finalDraft.material,
      tamanhoVariacao: finalDraft.tamanhoVariacao,
      quantidade: finalDraft.quantidade,
      reviewReasons: finalDraft.reviewReasons,
      rawSignals: finalDraft.rawSignals,
    );
  }

  static ScannerProductDraft mergeDrafts(
    ScannerProductDraft front,
    ScannerProductDraft back,
  ) {
    final conflicts = <String>[...front.reviewReasons, ...back.reviewReasons];
    ScannerField<T>? choose<T>(
      String field,
      ScannerField<T>? first,
      ScannerField<T>? second,
    ) {
      if (first?.value == null) return second;
      if (second?.value == null) return first;
      if (first!.value != second!.value) {
        conflicts.add('$field diverge entre frente e verso.');
      }
      return first;
    }

    return ScannerProductDraft(
      gtin: choose('GTIN', front.gtin, back.gtin),
      qr: choose('QR', front.qr, back.qr),
      referenciaComercial: choose(
        'Referência comercial',
        front.referenciaComercial,
        back.referenciaComercial,
      ),
      referenciaInterna: choose(
        'Referência interna',
        front.referenciaInterna,
        back.referenciaInterna,
      ),
      nome: choose('Nome', front.nome, back.nome),
      marca: choose('Marca', front.marca, back.marca),
      descricao: choose('Descrição', front.descricao, back.descricao),
      quantidadeEmbalagem: choose(
        'Quantidade',
        front.quantidadeEmbalagem,
        back.quantidadeEmbalagem,
      ),
      unidade: choose('Unidade', front.unidade, back.unidade),
      validade: choose('Validade', front.validade, back.validade),
      lote: choose('Lote', front.lote, back.lote),
      categoriaSugerida: choose(
        'Categoria',
        front.categoriaSugerida,
        back.categoriaSugerida,
      ),
      preco: choose('Preço', front.preco, back.preco),
      material: choose('Material', front.material, back.material),
      tamanhoVariacao: choose(
        'Tamanho/variação',
        front.tamanhoVariacao,
        back.tamanhoVariacao,
      ),
      quantidade: choose('Quantidade', front.quantidade, back.quantidade),
      imagemFrente: front.imagemFrente,
      imagemVerso: back.imagemVerso,
      reviewReasons: conflicts,
      rawSignals: {...front.rawSignals, ...back.rawSignals}.toList(),
    );
  }
}

class ProductLookupScannerProvider implements ScannerProvider {
  final ProductLookupService lookupService;
  final String commerceId;

  ProductLookupScannerProvider({
    required this.commerceId,
    ProductLookupService? lookupService,
  }) : lookupService = lookupService ?? ProductLookupService();

  @override
  Future<ScannerProductDraft?> searchBarcode(String gtin) async {
    final result = await lookupService.lookup(gtin, commerceId: commerceId);
    final product = result.product;
    if (product == null) return null;
    return ScannerProductDraft(
      gtin: ScannerField(
        result.normalizedGtin,
        source: product.source,
        confidence: ScannerConfidence.alta,
      ),
      nome: ScannerField(
        product.name,
        source: product.source,
        confidence: ScannerConfidence.alta,
      ),
      marca: product.brand == null
          ? null
          : ScannerField(
              product.brand,
              source: product.source,
              confidence: ScannerConfidence.alta,
            ),
      descricao: product.description == null
          ? null
          : ScannerField(
              product.description,
              source: product.source,
              confidence: ScannerConfidence.alta,
            ),
      categoriaSugerida: product.category == null
          ? null
          : ScannerField(
              product.category,
              source: product.source,
              confidence: ScannerConfidence.alta,
            ),
    );
  }

  @override
  Future<ScannerProductDraft?> analyzeImage(
    String imagePath, {
    bool isFront = true,
  }) async => null;
}
