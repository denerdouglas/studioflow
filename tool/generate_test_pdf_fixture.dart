import 'dart:convert';
import 'dart:io';

/// Gera uma representação Dart usada somente pelo integration test.
///
/// O arquivo produzido só entra no APK de teste porque é importado a partir de
/// `integration_test/`; ele não faz parte dos assets nem do app de produção.
void main() {
  const sourcePath = 'test/fixtures/5128.pdf';
  const targetPath = 'integration_test/fixtures/fixture_5128_bytes.dart';

  final source = File(sourcePath);
  if (!source.existsSync()) {
    stderr.writeln('Fixture não encontrada: $sourcePath');
    exitCode = 1;
    return;
  }

  final encoded = base64Encode(source.readAsBytesSync());
  final chunks = <String>[];
  for (var offset = 0; offset < encoded.length; offset += 100) {
    final end = (offset + 100).clamp(0, encoded.length);
    chunks.add("  '${encoded.substring(offset, end)}'");
  }

  final output = StringBuffer()
    ..writeln('// GENERATED FILE — TEST ONLY. DO NOT EDIT.')
    ..writeln(
      '// Generated from test/fixtures/5128.pdf by '
      'tool/generate_test_pdf_fixture.dart.',
    )
    ..writeln("import 'dart:convert';")
    ..writeln("import 'dart:typed_data';")
    ..writeln()
    ..writeln('final Uint8List fixture5128Bytes = base64Decode(')
    ..writeln(chunks.join('\n'))
    ..writeln(');');

  final target = File(targetPath)..parent.createSync(recursive: true);
  target.writeAsStringSync(output.toString());
}
