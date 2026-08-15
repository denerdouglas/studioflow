import 'package:studioflow/services/consignment_sheet_parser.dart';

void main() {
  const sheet = '''
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
  final result = ConsignmentSheetParser.parse(sheet);
  print(result.itens.length);
  for (final i in result.itens) {
    print('${i.codigo} - ${i.quantidade} - ${i.valorUnitario}');
  }
}
