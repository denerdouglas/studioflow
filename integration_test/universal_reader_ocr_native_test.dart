import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:studioflow/services/scanner/mlkit_vision_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('imagem fisica passa pelo ML Kit e parser reais', (tester) async {
    final directory = await getTemporaryDirectory();
    final fixture = File(
      '${directory.path}${Platform.pathSeparator}reader_ocr_fixture.png',
    );
    await fixture.writeAsBytes(await _sanitizedFixture(), flush: true);
    addTearDown(() async {
      if (await fixture.exists()) await fixture.delete();
    });

    expect(await fixture.exists(), isTrue);
    expect(await fixture.length(), greaterThan(0));

    // Sem provider substituto ou texto injetado: este caminho chama
    // TextRecognizer.processImage sobre o arquivo fisico criado no Android.
    final draft = await MlKitVisionProvider().analyzeImage(fixture.path);

    expect(draft, isNotNull);
    expect(draft!.referenciaComercial?.value, '524761');
    expect(draft.nome?.value?.toUpperCase(), contains('COLAR'));
    expect(draft.preco?.value, 195.0);
    expect(draft.material?.value?.toUpperCase(), 'OURO');
    expect(draft.rawSignals, isNotEmpty);
  });
}

Future<List<int>> _sanitizedFixture() async {
  const width = 1400;
  const height = 900;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 1400, 900),
    Paint()..color = Colors.white,
  );
  const lines = <String>[
    'COLAR CLASSICO',
    'CODIGO: 524761',
    'MATERIAL: OURO',
    'R\$ 195,00',
  ];
  var top = 90.0;
  for (final line in lines) {
    final painter = TextPainter(
      text: TextSpan(
        text: line,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 92,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width - 120);
    painter.paint(canvas, Offset(60, top));
    top += 180;
  }
  final image = await recorder.endRecording().toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (bytes == null) throw StateError('Nao foi possivel criar o fixture PNG.');
  return bytes.buffer.asUint8List();
}
