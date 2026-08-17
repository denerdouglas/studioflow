import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studioflow/screens/vision_scanner_page.dart';

void main() {
  testWidgets('VisionScannerPage - Modal Digitar codigo funciona corretamente', (WidgetTester tester) async {
    // Para nao precisar de camera real no test, o MobileScanner no widget test usa um mock
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => VisionScannerPage(returnList: true)),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Tocar em 'Digitar código manualmente'
    final digitarBtn = find.text('Digitar código manualmente');
    expect(digitarBtn, findsOneWidget);
    await tester.tap(digitarBtn);
    await tester.pumpAndSettle();

    // Modal abriu?
    expect(find.text('Digitar código'), findsOneWidget);

    // Cancelar
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    // Modal fechou
    expect(find.text('Digitar código'), findsNothing);
    
    debugDumpApp();

    // Tocar novamente
    await tester.tap(digitarBtn);
    await tester.pumpAndSettle();
    
    // Digitar algo
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pumpAndSettle();
    
    // Conferir tudo e Sair
    await tester.tap(find.text('Conferir tudo e Sair'));
    await tester.pumpAndSettle();
    
    // Deve ter fechado o modal E a pagina
    expect(find.text('Ler Etiqueta / Código'), findsNothing);
  });
}
