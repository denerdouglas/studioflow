import '../../models/domain/scanner_product_draft.dart';

abstract class ScannerProvider {
  Future<ScannerProductDraft?> searchBarcode(String gtin);
  Future<ScannerProductDraft?> analyzeImage(String imagePath, {bool isFront = true});
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
      gtin: ScannerField(gtin, source: 'barcode', confidence: ScannerConfidence.alta),
    );
  }

  /// Analisa frente e verso (se disponível) para criar um único Draft.
  Future<ScannerProductDraft> analyzeImages(String frontPath, {String? backPath}) async {
    ScannerProductDraft finalDraft = const ScannerProductDraft();
    
    // Tenta os provedores para a frente
    for (var provider in _externalProviders) {
      try {
        final frontDraft = await provider.analyzeImage(frontPath, isFront: true);
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
          final backDraft = await provider.analyzeImage(backPath, isFront: false);
          if (backDraft != null) {
            // Em uma implementação real profunda, faríamos um merge campo a campo
            // Aqui preservamos o principal da frente e enriquecemos.
            finalDraft = ScannerProductDraft(
              gtin: finalDraft.gtin ?? backDraft.gtin,
              nome: finalDraft.nome ?? backDraft.nome,
              marca: finalDraft.marca ?? backDraft.marca,
              descricao: finalDraft.descricao ?? backDraft.descricao,
              imagemFrente: frontPath,
              imagemVerso: backPath,
            );
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
      nome: finalDraft.nome,
      marca: finalDraft.marca,
    );
  }
}
