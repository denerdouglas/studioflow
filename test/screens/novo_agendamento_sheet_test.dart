import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:studioflow/screens/novo_agendamento_sheet.dart';

void main() {
  testWidgets(
    'NovoAgendamentoSheet deve exibir os botões de + Serviço e + Pacote simultaneamente',
    (WidgetTester tester) async {
      // Arrange
      final testDate = DateTime(2025, 10, 10);

      // Act
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NovoAgendamentoSheet(
              dataBase: testDate,
              profissionais: const [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Novo Agendamento'), findsOneWidget);
      expect(find.text('Agendamento'), findsOneWidget);
      expect(find.text('Bloqueio'), findsOneWidget);

      // Procura pelo botão "+ Serviço"
      expect(
        find.descendant(
          of: find.byType(TextButton),
          matching: find.text('Serviço'),
        ),
        findsOneWidget,
      );

      // Procura pelo botão "+ Pacote"
      expect(
        find.descendant(
          of: find.byType(TextButton),
          matching: find.text('Pacote'),
        ),
        findsOneWidget,
      );
    },
  );
}
