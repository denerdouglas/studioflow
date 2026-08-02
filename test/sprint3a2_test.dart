import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studioflow/screens/academico_stub_page.dart';
import 'package:studioflow/screens/marketplace_stub_page.dart';
import 'package:studioflow/widgets/shared/simple_bar_chart.dart';

void main() {
  group('Sprint 3A.2 - Menus e Stubs', () {
    testWidgets('AcademicoStubPage exibe estado de Em breve e sem cursos', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: AcademicoStubPage()));
      expect(find.text('Em breve!'), findsOneWidget);
      expect(find.text('Cursos Indisponíveis'), findsOneWidget);
    });

    testWidgets('MarketplaceStubPage exibe estado bloqueado', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: MarketplaceStubPage()));
      expect(find.text('Em breve!'), findsOneWidget);
      expect(find.text('Pesquisa Indisponível'), findsOneWidget);
      final disabledButton = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(disabledButton.onPressed, isNull);
    });

    testWidgets('SimpleBarChart exibe mensagem quando sem dados', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SimpleBarChart(data: []))));
      expect(find.text('Sem dados suficientes para o gráfico'), findsOneWidget);
    });

    testWidgets('SimpleBarChart exibe gráficos com dados reais', (tester) async {
      final data = [
        BarChartData('Jan', 10),
        BarChartData('Fev', 20),
      ];
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SimpleBarChart(data: data))));
      expect(find.text('Jan'), findsOneWidget);
      expect(find.text('Fev'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('20'), findsOneWidget);
    });
  });
}
