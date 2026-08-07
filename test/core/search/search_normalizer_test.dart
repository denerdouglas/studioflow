import 'package:flutter_test/flutter_test.dart';
import 'package:studioflow/core/search/search_normalizer.dart';

void main() {
  group('SearchNormalizer', () {
    test('deve remover acentos e converter para minúsculo', () {
      expect(SearchNormalizer.normalize('João'), 'joao');
      expect(SearchNormalizer.normalize('Mão'), 'mao');
      expect(SearchNormalizer.normalize('Pé'), 'pe');
      expect(SearchNormalizer.normalize('CABEÇA'), 'cabeca');
    });

    test('deve remover caracteres especiais', () {
      expect(SearchNormalizer.normalize('Corte & Barba!'), 'corte barba');
      expect(SearchNormalizer.normalize('produto@123'), 'produto123');
    });

    test('deve reduzir espaços múltiplos', () {
      expect(SearchNormalizer.normalize('  Corte   de    Cabelo  '), 'corte de cabelo');
    });

    test('deve retornar vazio se a string for vazia', () {
      expect(SearchNormalizer.normalize(''), '');
    });
  });
}
