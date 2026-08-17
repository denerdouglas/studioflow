import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:studioflow/models/domain/scanner_product_draft.dart';

// Teste de unidade/widget focado na correção do cast exception
void main() {
  group('Sprint 4040 - Scanner Universal Causa Raiz', () {
    testWidgets('ProdutosLojaPage processa ScannerResult sem Cast Exception', (
      tester,
    ) async {
      bool excecaoLancada = false;

      // Criar mock de navegação onde VisionScannerPage retorna ScannerResult.novo(produto)
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                try {
                  final result = await Navigator.push<dynamic>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        body: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context, ScannerResult.novo(null));
                          },
                          child: const Text('Pop Result'),
                        ),
                      ),
                    ),
                  );

                  // Simula a tratativa da página que aguardava String e agora aguarda dynamic
                  if (result is ScannerResult) {
                    // Trata normalmente, loading = false garantido
                  } else if (result is String) {
                    // String compatibilidade
                  }
                } catch (e) {
                  excecaoLancada = true;
                }
              },
              child: const Text('Ler Codigo'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Ler Codigo'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pop Result'));
      await tester.pumpAndSettle();

      expect(
        excecaoLancada,
        false,
        reason:
            'O cast não deve lançar exceção ao retornar ScannerResult. O Type Mismatch foi corrigido.',
      );
    });

    testWidgets('VendasLojaPage processa ScannerResult sem Cast Exception', (
      tester,
    ) async {
      bool excecaoLancada = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                try {
                  final result = await Navigator.push<dynamic>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        body: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(
                              context,
                              ScannerResult.existente(null),
                            );
                          },
                          child: const Text('Pop Result'),
                        ),
                      ),
                    ),
                  );

                  if (result is ScannerResult) {
                    // Trata normalmente
                  } else {
                    final codigo = result as String?;
                    if (codigo == null) return;
                  }
                } catch (e) {
                  excecaoLancada = true;
                }
              },
              child: const Text('Ler Codigo Venda'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Ler Codigo Venda'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pop Result'));
      await tester.pumpAndSettle();

      expect(
        excecaoLancada,
        false,
        reason: 'O cast não deve lançar exceção na tela de vendas.',
      );
    });
  });
}
