import 'package:flutter_test/flutter_test.dart';
import 'package:studioflow/services/vision_ocr_service.dart';

void main() {
  group('VisionOcrService - Resolução de Código', () {
    test('Deve extrair código numérico puro corretamente e não aceitar "Brinco" como código', () {
      final text = '''
        526839
        Brinco Prata
        R\$ 19,00
      ''';
      
      final result = VisionOcrService.parseText(text);
      
      expect(result.codigo, '526839');
      expect(result.nome, 'Brinco Prata');
      expect(result.preco, 19.0);
    });

    test('Deve priorizar código contextual em vez de palavra solta', () {
      final text = '''
        Ref: BRINCO1
        R\$ 49,90
        Brinco Ouro
      ''';
      
      final result = VisionOcrService.parseText(text);
      
      expect(result.codigo, 'BRINCO1');
      expect(result.nome, 'Brinco Ouro');
      expect(result.preco, 49.9);
    });

    test('Deve aceitar GTIN corretamente', () {
      final text = '''
        7894900700046
        Coca Cola
      ''';
      
      final result = VisionOcrService.parseText(text);
      
      expect(result.codigo, '7894900700046');
      expect(result.codigoTipo, ExtractedCodeKind.gtin);
      expect(result.nome, 'Coca Cola');
    });

    test('Não deve classificar nome simples sem contexto como código', () {
      final text = '''
        Anel
        R\$ 20,00
      ''';
      
      final result = VisionOcrService.parseText(text);
      
      // Sem numérico e sem contexto, não tem código.
      expect(result.codigo, isNull);
      expect(result.nome, 'Anel');
      expect(result.preco, 20.0);
    });
  });
}
