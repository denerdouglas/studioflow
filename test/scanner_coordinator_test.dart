import 'package:flutter_test/flutter_test.dart';
import 'package:studioflow/models/domain/scanner_product_draft.dart';
import 'package:studioflow/services/scanner/scanner_coordinator.dart';

class MockScannerProvider implements ScannerProvider {
  bool shouldThrow = false;
  ScannerProductDraft? draftToReturn;

  @override
  Future<ScannerProductDraft?> analyzeImage(String imagePath, {bool isFront = true}) async {
    if (shouldThrow) throw Exception('Provider error');
    return draftToReturn;
  }

  @override
  Future<ScannerProductDraft?> searchBarcode(String gtin) async {
    if (shouldThrow) throw Exception('Provider error');
    return draftToReturn;
  }
}

void main() {
  group('ScannerCoordinator Tests', () {
    test('Deve orquestrar captura limpa quando os provedores falharem', () async {
      final mock = MockScannerProvider()..shouldThrow = true;
      final coordinator = ScannerCoordinator(externalProviders: [mock]);

      final result = await coordinator.analyzeImages('front.jpg', backPath: 'back.jpg');

      // Draft deve retornar as imagens, mas campos vazios devido a falha (fallback manual)
      expect(result.imagemFrente, 'front.jpg');
      expect(result.imagemVerso, 'back.jpg');
      expect(result.gtin, isNull);
    });

    test('Deve mesclar informações de provedores válidos', () async {
      final mock = MockScannerProvider()
        ..draftToReturn = ScannerProductDraft(
          gtin: ScannerField('1234567890', source: 'mock', confidence: ScannerConfidence.baixa),
          nome: ScannerField('Produto Teste', source: 'mock', confidence: ScannerConfidence.alta),
        );
      final coordinator = ScannerCoordinator(externalProviders: [mock]);

      final result = await coordinator.analyzeImages('front.jpg');

      expect(result.imagemFrente, 'front.jpg');
      expect(result.gtin?.value, '1234567890');
      expect(result.gtin?.confidence, ScannerConfidence.baixa);
      expect(result.nome?.value, 'Produto Teste');
      expect(result.nome?.confidence, ScannerConfidence.alta);
    });

    test('Deve retornar barcode cru quando busca externa falha', () async {
      final mock = MockScannerProvider()..shouldThrow = true;
      final coordinator = ScannerCoordinator(externalProviders: [mock]);

      final result = await coordinator.searchExternalBarcode('987654');

      expect(result?.gtin?.value, '987654');
      expect(result?.gtin?.confidence, ScannerConfidence.alta);
      expect(result?.nome, isNull);
    });
  });
}
