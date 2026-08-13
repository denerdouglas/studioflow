import 'package:flutter_test/flutter_test.dart';
import 'package:studioflow/services/pricing_engine.dart';

void main() {
  test('materiais detalhados prevalecem sem duplicar custo estimado', () {
    final result = PricingEngine.calcularServico(
      const PricingInput(
        precoAtual: 100,
        custoBase: 80,
        custosMateriais: [10, 5],
        margemDesejadaPercentual: 30,
        comissaoPercentual: 10,
      ),
    );
    expect(result.custoConhecido, 15);
    expect(result.precoEquilibrio, closeTo(16.666, 0.01));
    expect(result.precoSugerido, closeTo(25, 0.01));
  });

  test('produto sem custo não é tratado como gratuito', () {
    final result = PricingEngine.calcularProduto(
      const PricingInput(
        precoAtual: 100,
        custoBase: 0,
        margemDesejadaPercentual: 30,
      ),
    );
    expect(result.custoConhecido, isNull);
    expect(result.margemAtualPercentual, isNull);
    expect(result.precoSugerido, isNull);
    expect(result.avisos.single, contains('NÃO TENHO DADOS SUFICIENTES'));
  });

  test('custo por hora é opcional e proporcional à duração', () {
    final result = PricingEngine.calcularServico(
      const PricingInput(
        precoAtual: 100,
        custoBase: 10,
        margemDesejadaPercentual: 20,
        duracaoMinutos: 30,
        custoHora: 40,
      ),
    );
    expect(result.custoConhecido, 30);
    expect(result.precoSugerido, 37.5);
  });
}
