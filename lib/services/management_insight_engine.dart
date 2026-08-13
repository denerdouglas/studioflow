import '../models/domain/centro_resultado.dart';

class ManagementInsight {
  final String titulo;
  final String explicacao;
  final String formula;

  const ManagementInsight(this.titulo, this.explicacao, this.formula);
}

abstract final class ManagementInsightEngine {
  static List<ManagementInsight> gerar({
    required ResumoCentroResultado atual,
    ResumoCentroResultado? anterior,
  }) {
    final insights = <ManagementInsight>[];
    if (anterior != null && anterior.faturamento > 0) {
      final change =
          (atual.faturamento - anterior.faturamento) /
          anterior.faturamento *
          100;
      insights.add(
        ManagementInsight(
          'Variação do faturamento',
          'O faturamento ${change >= 0 ? 'cresceu' : 'caiu'} ${change.abs().toStringAsFixed(1)}% em relação ao período comparável.',
          '(atual - anterior) ÷ anterior × 100',
        ),
      );
    }
    if (atual.centro == CentroResultado.geral && atual.faturamento > 0) {
      insights.add(
        ManagementInsight(
          'Composição do faturamento',
          'Salão representa ${(atual.salao / atual.faturamento * 100).toStringAsFixed(1)}% e Loja ${(atual.loja / atual.faturamento * 100).toStringAsFixed(1)}%.',
          'centro ÷ faturamento consolidado × 100',
        ),
      );
    }
    if (atual.aReceber > 0) {
      insights.add(
        ManagementInsight(
          'Valores a receber',
          'Há valores faturados ou cobrados que ainda não entraram no caixa.',
          'valor operacional - pagamentos confirmados',
        ),
      );
    }
    if (atual.dadosAusentes.isNotEmpty) {
      insights.add(
        ManagementInsight(
          'Dados incompletos',
          atual.dadosAusentes.join(' '),
          'validação das fontes antes do cálculo',
        ),
      );
    }
    return insights;
  }
}
