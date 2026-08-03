import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studioflow/screens/assinaturas_page.dart';

void main() {
  group('Sprint 3B.1 - Assinaturas', () {
    testWidgets(
      'AssinaturasPage informa configuração pendente sem oferecer compra',
      (tester) async {
        await tester.pumpWidget(const MaterialApp(home: AssinaturasPage()));

        await tester.pumpAndSettle(const Duration(seconds: 1));

        expect(find.text('Configuração pendente'), findsOneWidget);
        expect(find.text('Plano Fundador StudioFlow'), findsNothing);
        expect(find.text('20 DIAS GRÁTIS'), findsNothing);
        expect(find.text('Assinar Agora'), findsNothing);
        expect(
          find.textContaining('Nenhuma compra pode ser realizada'),
          findsOneWidget,
        );
      },
    );
  });
}
