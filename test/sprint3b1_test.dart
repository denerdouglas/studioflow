import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studioflow/screens/assinaturas_page.dart';

void main() {
  group('Sprint 3B.1 - Assinaturas', () {
    testWidgets(
      'AssinaturasPage carrega estado inativo com cobrança desativada na homologação',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: AssinaturasPage(),
          ),
        );

        await tester.pumpAndSettle(
          const Duration(seconds: 1),
        );

        expect(
          find.text('Plano Fundador StudioFlow'),
          findsOneWidget,
        );

        expect(
          find.text('20 DIAS GRÁTIS'),
          findsOneWidget,
        );

        expect(
          find.text('Indisponível na Homologação'),
          findsOneWidget,
        );

        expect(
          find.text('Restaurar Compras (Desativado)'),
          findsOneWidget,
        );

        expect(
          find.text('Assinar Agora'),
          findsNothing,
        );
      },
    );
  });
}