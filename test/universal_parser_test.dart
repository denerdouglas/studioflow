import 'package:flutter_test/flutter_test.dart';
import 'package:studioflow/services/consignment_sheet_parser.dart';

void main() {
  group('Universal Document Parser', () {
    test('Deve processar PDF do fornecedor com 100 itens (Exemplo)', () {
      final text = '''
CABEÇALHO DA REMESSA
FORNECEDOR: Representante Exemplo
DATA ENVIO: 10/08/2026
CONTRATO: 9999
SACOLA: 42

CATEGORIA 1
BABY DOLL | 3415 | 1 | R\$ 48,90
PIJAMA | 1305 | 1 | R\$ 47,90

CATEGORIA 2
CALCINHA | 109 | 1 | R\$ 29,90
TOP | 158 | 1 | R\$ 53,90

CONJUNTO | 1267 | 1 | R\$ 87,90
BOXER | 5 | 1 | R\$ 89,90
CAMISOLA | 2631 | 1 | R\$ 151,90

TOTAL DE ITENS 7
VALOR TOTAL R\$ 508,30
''';

      final parsed = ConsignmentSheetParser.parse(text);

      expect(parsed.representante, 'Representante Exemplo');
      expect(parsed.contrato, '9999');
      expect(parsed.itens.length, 7);

      final i1 = parsed.itens[0];
      expect(i1.codigo, '3415');
      expect(i1.descricao.toUpperCase(), 'BABY DOLL');
      expect(i1.quantidade, 1);
      expect(i1.valorUnitario, 48.90);

      final i3 = parsed.itens[2];
      expect(i3.codigo, '109');
      expect(i3.descricao.toUpperCase(), 'CALCINHA');
      expect(i3.quantidade, 1);
      expect(i3.valorUnitario, 29.90);

      final i6 = parsed.itens[5];
      expect(i6.codigo, '5');
      expect(i6.descricao.toUpperCase(), 'BOXER');
      expect(i6.quantidade, 1);
      expect(i6.valorUnitario, 89.90);

      expect(parsed.quantidadeDeclarada, 7);
      expect(parsed.totalDeclarado, 508.30);
    });

    test('Deve suportar formato posicional sem pipes', () {
      final text = '''
3415 BABY DOLL 1 48,90
PIJAMA 1305 1 R\$ 47,90
109 CALCINHA 1 29.90
158 TOP 1 53,90
1267 CONJUNTO 1 87.90
5 BOXER 1 89.90
2631 CAMISOLA 1 151.90
''';
      final parsed = ConsignmentSheetParser.parse(text);
      expect(parsed.itens.length, 7);

      expect(parsed.itens[0].codigo, '3415');
      expect(parsed.itens[0].descricao.toUpperCase(), 'BABY DOLL');

      expect(parsed.itens[1].codigo, '1305');
      expect(parsed.itens[1].descricao.toUpperCase(), 'PIJAMA');

      expect(parsed.itens[2].codigo, '109');
      expect(parsed.itens[2].descricao.toUpperCase(), 'CALCINHA');
    });
  });
}
