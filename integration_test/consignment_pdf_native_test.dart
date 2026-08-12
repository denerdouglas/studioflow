import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:studioflow/services/consignment_document_import_service.dart';

import 'fixtures/fixture_5128_bytes.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('importa o PDF 5128 pelo pipeline nativo real', (tester) async {
    final fixtureBytes = fixture5128Bytes;
    expect(fixtureBytes, isNotEmpty);

    final temporaryDirectory = await getTemporaryDirectory();
    final fixture = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}consignment_fixture_5128.pdf',
    );
    await fixture.writeAsBytes(fixtureBytes, flush: true);
    addTearDown(() async {
      if (await fixture.exists()) await fixture.delete();
    });
    expect(await fixture.length(), fixtureBytes.length);

    // Sem extratores injetados: usa ReadPdfText.getPDFtext em produção.
    final result = await ConsignmentDocumentImportService().importPdf(
      fixture.path,
    );

    expect(result.usedOcr, isFalse);
    expect(result.representante, 'RAFAELA RODRIGUES DA SILVA');
    expect(result.mostruario, '1.569');
    expect(result.contrato, '206.698');
    expect(result.dataEnvio, DateTime(2026, 8, 7));
    expect(result.dataTroca, DateTime(2026, 9, 9));
    expect(result.dataPagamento, DateTime(2026, 10, 8));
    expect(result.zonaVenda, 'BARUERI T 1');

    expect(result.quantidadeImportada, 338);
    expect(result.totalImportado, 26390.0);
    expect(result.quantidadeDeclarada, 338);
    expect(result.totalDeclarado, 26390.0);
    expect(result.divergeDoDeclarado, isFalse);

    expect(
      result.itens.map((item) => item.categoria).toSet(),
      containsAll(<String>{
        'Anel',
        'Brinco',
        'Corrente',
        'Pingente',
        'Pulseira',
        'Tornozeleira',
      }),
    );
    expect(
      result.itens.map((item) => item.material).toSet(),
      containsAll(<String>{'Ouro', 'Prata', 'Inox'}),
    );

    final codes = result.itens.map((item) => item.codigo).toList();
    expect(codes, containsAll(<String>['R00018', 'R00013', 'R0013', 'R0026']));
    expect(codes.where((code) => code == '527005'), hasLength(2));
    expect(codes.where((code) => code == '528299'), hasLength(2));
    expect(codes, containsAll(<String>['89102', '90790', '105049']));

    // O pipeline retorna somente uma prévia em memória. A confirmação e a
    // persistência pertencem à tela/repositório e não são chamadas aqui.
    expect(result.itens, isNotEmpty);
  });
}
