import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/repositories/consignacao_conferencia_repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ConsignacaoConferenciaRepository', () {
    test('Enum e tipagem de ConsignacaoResolveResult estão corretas', () {
      const result = ConsignacaoResolveResult(
        state: ConsignacaoResolveState.encontrada,
        peca: {'id': '123', 'nome': 'Anel'},
      );

      expect(result.state, ConsignacaoResolveState.encontrada);
      expect(result.peca?['id'], '123');
      expect(result.multiplasOpcoes, isEmpty);
    });

    test('ConsignacaoResolveResult pode ter múltiplas opções', () {
      const result = ConsignacaoResolveResult(
        state: ConsignacaoResolveState.multiplas,
        multiplasOpcoes: [
          {'id': '123', 'nome': 'Anel'},
          {'id': '456', 'nome': 'Anel 2'},
        ],
      );

      expect(result.state, ConsignacaoResolveState.multiplas);
      expect(result.multiplasOpcoes.length, 2);
    });
  });
}
