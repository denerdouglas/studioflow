import 'package:flutter_test/flutter_test.dart';
import 'package:studioflow/models/domain/scanner_product_draft.dart';
import 'package:studioflow/models/domain/universal_reader.dart';
import 'package:studioflow/services/scanner/mlkit_vision_provider.dart';
import 'package:studioflow/services/scanner/scanner_coordinator.dart';

void main() {
  group('Leitor Universal - campos reais', () {
    test('etiqueta de joia preserva código comercial e não inventa GTIN', () {
      final result = MlKitVisionProvider.parseRecognizedText(
        '524761\nR\$ 195,00\nCOLAR OURO',
      );
      expect(result.codigoComercial, '524761');
      expect(result.gtin, isNull);
      expect(result.preco?.value, 195);
      expect(result.nome?.value, contains('COLAR'));
      expect(result.descricao?.value, isNull);
      expect(result.categoriaSugerida, isNull);
      expect(result.marca, isNull);
      expect(result.material?.value?.toUpperCase(), contains('OURO'));
      expect(result.tamanhoVariacao, isNull);
      expect(result.unidade, isNull);
      expect(result.quantidade, isNull);
      expect(result.precisaRevisao, isTrue);
    });

    test('barcode e etiqueta se complementam sem trocar preço e código', () {
      const barcode = ScannerProductDraft(
        gtin: ScannerField(
          '7894900011517',
          source: 'barcode',
          confidence: ScannerConfidence.alta,
        ),
      );
      final label = MlKitVisionProvider.parseRecognizedText(
        'Calcinha Fio Dental Cós Largo\nTamanho: P\nR\$ 29,90',
      );
      final result = ScannerCoordinator.mergeDrafts(barcode, label);
      expect(result.gtin?.value, '7894900011517');
      expect(result.codigoComercial, isNull);
      expect(result.nome?.value, contains('Calcinha'));
      expect(result.preco?.value, 29.90);
      expect(result.tamanhoVariacao?.value, 'P');
      expect(result.material, isNull);
      expect(result.categoriaSugerida, isNull);
      expect(result.unidade, isNull);
      expect(result.quantidade, isNull);
      expect(result.precisaRevisao, isTrue);
    });

    test('OCR ambíguo preserva caracteres e exige revisão', () {
      for (final value in ['R0O18', 'I1l5S8B2Z']) {
        final result = MlKitVisionProvider.parseRecognizedText(value);
        expect(result.codigoComercial, value);
        expect(result.precisaRevisao, isTrue);
      }
    });
  });

  group('sessão temporária do Modo Bip', () {
    test('20 leituras distintas permanecem confirmáveis', () {
      final session = BipSessionController();
      for (var i = 0; i < 20; i++) {
        expect(
          session.add(
            BipSessionItem(
              id: 'item_$i',
              deduplicationKey: 'code_$i',
              draft: ScannerProductDraft(
                referenciaComercial: ScannerField('code_$i'),
              ),
            ),
          ),
          isTrue,
        );
        session.confirm('item_$i');
      }
      expect(session.counters.read, 20);
      expect(session.counters.confirmed, 20);
    });

    test('duplicidade, erro, edição e remoção não perdem anteriores', () {
      final session = BipSessionController();
      const original = BipSessionItem(
        id: '1',
        deduplicationKey: 'same',
        draft: ScannerProductDraft(
          nome: ScannerField('Original'),
          reviewReasons: ['Revisar'],
        ),
      );
      expect(session.add(original), isTrue);
      expect(session.add(original), isFalse);
      session.registerError();
      session.update(
        '1',
        const ScannerProductDraft(nome: ScannerField('Corrigido')),
      );
      expect(session.items.single.draft.nome?.value, 'Corrigido');
      expect(session.counters.duplicates, 1);
      expect(session.counters.errors, 1);
      session.remove('1');
      expect(session.items, isEmpty);
    });

    test('política nunca autoriza persistência durante leitura', () {
      for (final context in ReaderContext.values) {
        expect(ReaderContextPolicy.forContext(context).persistsOnRead, isFalse);
      }
    });
  });
}
