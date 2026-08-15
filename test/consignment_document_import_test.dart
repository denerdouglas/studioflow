import 'package:flutter_test/flutter_test.dart';
import 'package:studioflow/services/consignment_document_import_service.dart';
import 'package:studioflow/services/consignment_sheet_parser.dart';

const _sheet = '''
REPRESENT: Maria Joias
MOSTRUÁRIO: 2026-08
CONTRATO: CTR-99
DATA ENVIO: 01/08/2026
DATA TROCA: 01/09/2026
DATA PAGTO: 05/09/2026
ZONA VENDA: BARUERI T 1
001 - ANEL
*** OURO
Produto Qtd Val Un | Produto Qtd Val Un | Produto Qtd Val Un
89102 1 89,00    89749 2 112,00    88030 1 69,00
linha 999999 sem quantidade nem preço
002 - BRINCO
*** PRATA
88379 1 75,00
338 Itens Total 26.390,00
''';

void main() {
  test('parser reconhece cabeçalho, datas, categorias e materiais', () {
    final result = ConsignmentSheetParser.parse(_sheet);
    expect(result.representante, 'Maria Joias');
    expect(result.mostruario, '2026-08');
    expect(result.contrato, 'CTR-99');
    expect(result.dataEnvio, DateTime(2026, 8, 1));
    expect(result.dataTroca, DateTime(2026, 9, 1));
    expect(result.dataPagamento, DateTime(2026, 9, 5));
    expect(result.zonaVenda, 'BARUERI T 1');
    expect(result.itens, hasLength(4));
    expect(result.itens.first.codigo, '89102');
    expect(result.itens.first.categoria, 'Anel');
    expect(result.itens.first.material, 'Ouro');
    expect(result.itens.first.valorUnitario, 89.0);
    expect(result.itens[1].quantidade, 2);
    expect(result.itens.last.categoria, 'Brinco');
    expect(result.itens.last.material, 'Prata');
    expect(result.linhasPendentes, hasLength(1));
    expect(result.linhasPendentes.single.lineNumber, 12);
    expect(result.linhasPendentes.single.originalText, contains('999999'));
    expect(result.linhasPendentes.single.reason, 'Quantidade ambígua');
    expect(result.quantidadeDeclarada, 338);
    expect(result.totalDeclarado, 26390.0);
    expect(result.divergeDoDeclarado, isTrue);
  });

  test(
    'códigos alfanuméricos e repetidos são preservados como ocorrências',
    () {
      final result = ConsignmentSheetParser.parse('''
003 - CORRENTE
*** INOX
R00018 1 10,00 R00013 1 20,00 R0013 2 30,00
527005 1 40,00 527005 1 40,00 528299 1 50,00
528299 1 50,00 R0026 1 60,00
9 Itens Total 330,00
''');
      expect(result.itens.map((item) => item.codigo), [
        'R00018',
        'R00013',
        'R0013',
        '527005',
        '527005',
        '528299',
        '528299',
        'R0026',
      ]);
      expect(
        result.itens.where((item) => item.codigo == '527005'),
        hasLength(2),
      );
      expect(
        result.itens.where((item) => item.codigo == '528299'),
        hasLength(2),
      );
      expect(result.itens.every((item) => item.material == 'Inox'), isTrue);
      expect(result.quantidadeImportada, 9);
      expect(result.totalImportado, 330.0);
      expect(result.quantidadeDeclarada, 9);
      expect(result.totalDeclarado, 330.0);
      expect(result.divergeDoDeclarado, isFalse);
    },
  );

  test('documento sem rodapé declarado não força comparação', () {
    final result = ConsignmentSheetParser.parse('''
006 - TORNOZELEIRA
*** TITÂNIO
ABC001 1 99,90
''');
    expect(result.quantidadeDeclarada, isNull);
    expect(result.totalDeclarado, isNull);
    expect(result.divergeDoDeclarado, isFalse);
    expect(result.itens.single.material, 'Titânio');
  });

  test('linha com três colunas gera três DTOs independentes', () {
    final result = ConsignmentSheetParser.parse('''
001 - ANEL
*** OURO
89102 1 89,00 89749 1 112,00 88030 3 69,00
''');
    expect(result.itens.map((item) => item.codigo), [
      '89102',
      '89749',
      '88030',
    ]);
    expect(result.itens.last.quantidade, 3);
    expect(result.itens.last.toPieceMap(), {
      'codigo': '88030',
      'categoria': 'Anel',
      'nome': 'Anel',
      'descricao': 'Anel',
      'quantidade': 3,
      'preco': 69.0,
      'material': 'Ouro',
      'observacoes': '',
    });
  });

  test('PDF com texto embutido não executa OCR desnecessário', () async {
    var embeddedCalls = 0;
    var ocrCalls = 0;
    final service = ConsignmentDocumentImportService(
      embeddedExtractor: (_) async {
        embeddedCalls++;
        return _sheet;
      },
      pdfOcrExtractor: (_) async {
        ocrCalls++;
        return _sheet;
      },
    );
    final result = await service.importPdf('folha.pdf');
    expect(result.itens, hasLength(4));
    expect(result.usedOcr, isFalse);
    expect(embeddedCalls, 1);
    expect(ocrCalls, 0);
  });

  test('PDF digitalizado sem texto útil usa fallback OCR real', () async {
    var ocrCalls = 0;
    final service = ConsignmentDocumentImportService(
      embeddedExtractor: (_) async => '   ',
      pdfOcrExtractor: (_) async {
        ocrCalls++;
        return _sheet;
      },
    );
    final result = await service.importPdf('digitalizado.pdf');
    expect(result.usedOcr, isTrue);
    expect(result.itens, hasLength(4));
    expect(ocrCalls, 1);
  });

  test('linhas inválidas não derrubam itens válidos', () {
    final result = ConsignmentSheetParser.parse('''
001 - ANEL
texto inválido
89102 1 89,00
508245 quantidade ausente
''');
    expect(result.itens.single.codigo, '89102');
    expect(result.linhasPendentes, hasLength(1));
  });

  test('texto lido sem produto gera erro claro', () async {
    final service = ConsignmentDocumentImportService(
      embeddedExtractor: (_) async =>
          'REPRESENTANTE: Maria\nCONTRATO: ABC\nDocumento sem produtos',
    );
    await expectLater(
      service.importPdf('sem-produtos.pdf'),
      throwsA(
        isA<ConsignmentImportException>().having(
          (error) => error.message,
          'message',
          'Nenhum produto identificado. Nenhuma estratégia (Texto/OCR) conseguiu extrair dados utilizáveis deste documento.',
        ),
      ),
    );
  });

  test('PDF ilegível após OCR gera erro de extração claro', () async {
    final service = ConsignmentDocumentImportService(
      embeddedExtractor: (_) async => '',
      pdfOcrExtractor: (_) async => '',
    );
    await expectLater(
      service.importPdf('ilegivel.pdf'),
      throwsA(
        isA<ConsignmentImportException>().having(
          (error) => error.message,
          'message',
          'Não foi possível extrair os itens deste PDF.',
        ),
      ),
    );
  });

  test('JPG/PNG continua usando ML Kit e alimenta os mesmos DTOs', () async {
    var imageCalls = 0;
    final service = ConsignmentDocumentImportService(
      imageRecognizer: (_) async {
        imageCalls++;
        return _sheet;
      },
    );
    final result = await service.importImage('folha.jpg');
    expect(result.usedOcr, isTrue);
    expect(result.itens, hasLength(4));
    expect(imageCalls, 1);
  });
}
