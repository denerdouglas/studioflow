import 'dart:math' as math;

class MultiunitPricingConfig {
  final int includedUnits;
  final double additionalUnitPrice;
  final int includedCollaborators;
  final int collaboratorBlockSize;
  final double collaboratorBlockPrice;

  const MultiunitPricingConfig({
    this.includedUnits = 1,
    this.additionalUnitPrice = 10,
    this.includedCollaborators = 3,
    this.collaboratorBlockSize = 3,
    this.collaboratorBlockPrice = 10,
  });
}

class MultiunitPriceQuote {
  final double basePrice;
  final int additionalUnits;
  final int collaboratorBlocks;
  final double unitsAmount;
  final double collaboratorsAmount;

  const MultiunitPriceQuote({
    required this.basePrice,
    required this.additionalUnits,
    required this.collaboratorBlocks,
    required this.unitsAmount,
    required this.collaboratorsAmount,
  });

  double get total => basePrice + unitsAmount + collaboratorsAmount;
}

class MultiunitPricingEngine {
  final MultiunitPricingConfig config;
  const MultiunitPricingEngine({this.config = const MultiunitPricingConfig()});

  MultiunitPriceQuote quote({
    required double basePrice,
    required int activeUnits,
    required int billableCollaborators,
  }) {
    if (basePrice < 0 || activeUnits < 0 || billableCollaborators < 0) {
      throw ArgumentError('Quantidades e preço não podem ser negativos.');
    }
    final units = math.max(0, activeUnits - config.includedUnits);
    final excess = math.max(
      0,
      billableCollaborators - config.includedCollaborators,
    );
    final blocks = (excess / config.collaboratorBlockSize).ceil();
    return MultiunitPriceQuote(
      basePrice: basePrice,
      additionalUnits: units,
      collaboratorBlocks: blocks,
      unitsAmount: units * config.additionalUnitPrice,
      collaboratorsAmount: blocks * config.collaboratorBlockPrice,
    );
  }
}
