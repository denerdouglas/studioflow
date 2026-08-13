class PricingInput {
  final double precoAtual;
  final double? custoBase;
  final List<double> custosMateriais;
  final double comissaoPercentual;
  final double taxasPercentual;
  final double margemDesejadaPercentual;
  final double custoAdicional;
  final int? duracaoMinutos;
  final double? custoHora;
  final double? metaHora;

  const PricingInput({
    required this.precoAtual,
    required this.margemDesejadaPercentual,
    this.custoBase,
    this.custosMateriais = const [],
    this.comissaoPercentual = 0,
    this.taxasPercentual = 0,
    this.custoAdicional = 0,
    this.duracaoMinutos,
    this.custoHora,
    this.metaHora,
  });
}

class PricingResult {
  final double precoAtual;
  final double? custoConhecido;
  final double comissao;
  final double? margemAtualPercentual;
  final double? precoEquilibrio;
  final double? precoSugerido;
  final bool parcial;
  final List<String> avisos;
  final List<String> premissas;

  const PricingResult({
    required this.precoAtual,
    required this.custoConhecido,
    required this.comissao,
    required this.margemAtualPercentual,
    required this.precoEquilibrio,
    required this.precoSugerido,
    required this.parcial,
    required this.avisos,
    required this.premissas,
  });
}

abstract final class PricingEngine {
  static PricingResult calcularServico(PricingInput input) {
    final detailed = input.custosMateriais
        .where((value) => value >= 0)
        .toList();
    final hasDetailed = detailed.isNotEmpty;
    final hasFallback = input.custoBase != null && input.custoBase! > 0;
    final materialCost = hasDetailed
        ? detailed.fold<double>(0, (sum, value) => sum + value)
        : (hasFallback ? input.custoBase! : 0);
    final timeCost = input.custoHora != null && input.duracaoMinutos != null
        ? input.custoHora! * input.duracaoMinutos! / 60
        : 0.0;
    final known = materialCost + timeCost + input.custoAdicional;
    final complete = hasDetailed || hasFallback;
    return _calculate(
      input,
      complete ? known : null,
      premises: [
        if (hasDetailed)
          'Materiais detalhados prevalecem sobre custo estimado.',
        if (!hasDetailed && hasFallback)
          'Custo estimado usado porque não há materiais detalhados.',
        if (timeCost > 0) 'Custo/hora proporcional à duração incluído.',
        if (input.metaHora != null && input.duracaoMinutos != null)
          'Meta por hora usada como piso adicional da sugestão.',
      ],
      targetFloor: input.metaHora != null && input.duracaoMinutos != null
          ? input.metaHora! * input.duracaoMinutos! / 60
          : null,
    );
  }

  static PricingResult calcularProduto(PricingInput input) {
    final validCost = input.custoBase != null && input.custoBase! > 0;
    return _calculate(
      input,
      validCost ? input.custoBase! + input.custoAdicional : null,
      premises: const ['Custo zero é tratado como custo não informado.'],
    );
  }

  static PricingResult _calculate(
    PricingInput input,
    double? cost, {
    required List<String> premises,
    double? targetFloor,
  }) {
    final variable = (input.comissaoPercentual + input.taxasPercentual) / 100;
    final target = input.margemDesejadaPercentual / 100;
    final warnings = <String>[];
    if (cost == null) {
      warnings.add(
        'NÃO TENHO DADOS SUFICIENTES: custo não cadastrado; margem indisponível.',
      );
    }
    if (variable >= 1 || variable + target >= 1) {
      warnings.add(
        'Percentuais informados não permitem formar um preço válido.',
      );
    }
    final commission = input.precoAtual * input.comissaoPercentual / 100;
    final margin = cost == null || input.precoAtual <= 0
        ? null
        : (input.precoAtual - cost - input.precoAtual * variable) /
              input.precoAtual *
              100;
    final breakEven = cost == null || variable >= 1
        ? null
        : cost / (1 - variable);
    var suggested = cost == null || variable + target >= 1
        ? null
        : cost / (1 - variable - target);
    if (suggested != null && targetFloor != null && suggested < targetFloor) {
      suggested = targetFloor;
    }
    return PricingResult(
      precoAtual: input.precoAtual,
      custoConhecido: cost,
      comissao: commission,
      margemAtualPercentual: margin,
      precoEquilibrio: breakEven,
      precoSugerido: suggested,
      parcial: cost == null,
      avisos: warnings,
      premissas: premises,
    );
  }
}
