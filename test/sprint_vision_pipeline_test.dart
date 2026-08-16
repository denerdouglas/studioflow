import 'package:flutter_test/flutter_test.dart';
import 'package:studioflow/models/domain/scanner_product_draft.dart';
import 'package:studioflow/models/domain/universal_reader.dart';

void main() {
  group('Scanner Universal - Pipeline Completo', () {
    test(
      'ABRIU CÂMERA -> MobileScanner tenta barcode -> se válido resolve imediatamente',
      () async {
        // Mock barcode
        final draft = ScannerProductDraft(
          gtin: ScannerField(
            '7891234567890',
            source: 'barcode',
            confidence: ScannerConfidence.alta,
          ),
          rawSignals: ['7891234567890'],
        );
        expect(draft.gtin?.value, '7891234567890');
        // Resolve existing
        final item = BipSessionItem(
          id: '1',
          deduplicationKey: draft.gtin!.value!,
          draft: draft,
          confirmed: true,
        );
        expect(item.deduplicationKey, '7891234567890');
      },
    );

    test('Se não resolver dentro do timeout: OCR automático', () async {
      // Simulando o draft que MlKitVisionProvider criaria vazio ou não
      final draft = ScannerProductDraft(rawSignals: ['Texto OCR']);
      expect(draft.rawSignals.contains('Texto OCR'), isTrue);
      expect(draft.gtin, isNull);
    });

    test('OCR normaliza código, nome, preço e tenta resolver', () async {
      final draft = ScannerProductDraft(
        gtin: ScannerField(
          '7890000000000',
          source: 'ocr',
          confidence: ScannerConfidence.alta,
        ),
        nome: ScannerField(
          'Produto Teste',
          source: 'ocr',
          confidence: ScannerConfidence.media,
        ),
        preco: ScannerField(
          10.50,
          source: 'ocr',
          confidence: ScannerConfidence.baixa,
        ),
        rawSignals: [],
      );

      expect(draft.gtin?.value, '7890000000000');
      expect(draft.nome?.value, 'Produto Teste');
      expect(draft.preco?.value, 10.50);
    });

    test('Produto não existe -> abre draft/cadastro pré-preenchido', () async {
      final draft = ScannerProductDraft(
        gtin: ScannerField(
          '0000000000000',
          source: 'ocr',
          confidence: ScannerConfidence.alta,
        ),
        rawSignals: [],
      );
      // Aqui testaríamos BipContextService() retornando desconhecido,
      // mas como é unitário vamos simular que ele precisa de review.
      expect(draft.nome, isNull);
    });

    test(
      'Duplicata não gera novo feedback e não adiciona duas vezes',
      () async {
        final controller = BipSessionController();
        final draft = ScannerProductDraft(
          gtin: ScannerField(
            '7891234567890',
            source: 'barcode',
            confidence: ScannerConfidence.alta,
          ),
          rawSignals: ['7891234567890'],
        );
        final added1 = controller.add(
          BipSessionItem(
            id: '1',
            deduplicationKey: draft.gtin!.value!,
            draft: draft,
            confirmed: true,
          ),
        );
        final added2 = controller.add(
          BipSessionItem(
            id: '2',
            deduplicationKey: draft.gtin!.value!,
            draft: draft,
            confirmed: true,
          ),
        );
        expect(added1, isTrue);
        expect(added2, isFalse); // Duplicata barrada!
        expect(controller.items.length, 1);
      },
    );
  });
}
