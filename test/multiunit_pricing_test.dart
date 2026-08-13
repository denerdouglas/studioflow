import 'package:flutter_test/flutter_test.dart';
import 'package:studioflow/core/config/multiunit_pricing.dart';

void main() {
  const engine = MultiunitPricingEngine();

  test('faixas de colaboradores são calculadas em blocos de três', () {
    for (final entry in <int, double>{
      0: 0,
      1: 0,
      3: 0,
      4: 10,
      6: 10,
      7: 20,
      9: 20,
      10: 30,
      12: 30,
    }.entries) {
      expect(
        engine
            .quote(
              basePrice: 34.90,
              activeUnits: 1,
              billableCollaborators: entry.key,
            )
            .collaboratorsAmount,
        entry.value,
      );
    }
  });

  test('unidades e colaboradores adicionais somam ao preço real', () {
    final quote = engine.quote(
      basePrice: 34.90,
      activeUnits: 3,
      billableCollaborators: 8,
    );
    expect(quote.additionalUnits, 2);
    expect(quote.collaboratorBlocks, 2);
    expect(quote.unitsAmount, 20);
    expect(quote.collaboratorsAmount, 20);
    expect(quote.total, closeTo(74.90, 0.001));
  });
}
