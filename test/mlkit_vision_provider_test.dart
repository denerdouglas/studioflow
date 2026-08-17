import 'package:flutter_test/flutter_test.dart';
import 'package:studioflow/services/scanner/mlkit_vision_provider.dart';
import 'package:studioflow/services/vision_ocr_service.dart';

void main() {
  test('MlKitVisionProvider - Preserva zeros a esquerda em codigo comercial', () {
    final text = '''
    Codigo: 00123
    Preço: R\$ 112,00
    Tamanho: M
    ''';
    final draft = MlKitVisionProvider.parseRecognizedText(text);
    expect(draft.referenciaComercial?.value, '00123');
    expect(draft.preco?.value, 112.00);
    expect(draft.tamanhoVariacao?.value, 'M');
  });

  test('VisionOcrService - Corrige parsing de preco x100 (bug da virgula)', () {
    final text1 = 'R\$ 112,00';
    final tag1 = VisionOcrService.parseText(text1);
    expect(tag1.preco, 112.00);

    final text2 = 'R\$ 112.00';
    final tag2 = VisionOcrService.parseText(text2);
    expect(tag2.preco, 112.00);

    final text3 = '1.000,00';
    final tag3 = VisionOcrService.parseText(text3);
    expect(tag3.preco, 1000.00);

    final text4 = 'R\$ 1.000';
    final tag4 = VisionOcrService.parseText(text4);
    expect(tag4.preco, 1000.00);
  });
}
