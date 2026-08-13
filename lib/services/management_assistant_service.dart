import '../core/helpers/app_formatters.dart';
import '../models/domain/centro_resultado.dart';
import '../repositories/centro_resultado_repository.dart';
import 'management_insight_engine.dart';

class ManagementAnswer {
  final String texto;
  final ResumoCentroResultado resumo;
  final List<ManagementInsight> insights;

  const ManagementAnswer({
    required this.texto,
    required this.resumo,
    required this.insights,
  });
}

class ManagementAssistantService {
  final CentroResultadoRepository repository;

  ManagementAssistantService(this.repository);

  Future<ManagementAnswer> responder(
    String pergunta, {
    CentroResultado contexto = CentroResultado.geral,
    PeriodoGestao? periodo,
  }) async {
    final text = pergunta.toLowerCase();
    final center = text.contains('loja')
        ? CentroResultado.loja
        : text.contains('salão') || text.contains('salao')
        ? CentroResultado.salao
        : contexto;
    final selected =
        periodo ??
        (text.contains('hoje')
            ? PeriodoGestao.doTipo(PeriodoGestaoTipo.hoje)
            : PeriodoGestao.doTipo(PeriodoGestaoTipo.mes));
    final summary = await repository.resumo(center, selected);
    final duration = selected.fimExclusivo.difference(selected.inicio);
    final previous = await repository.resumo(
      center,
      PeriodoGestao(
        inicio: selected.inicio.subtract(duration),
        fimExclusivo: selected.inicio,
        tipo: PeriodoGestaoTipo.personalizado,
      ),
    );
    final insights = ManagementInsightEngine.gerar(
      atual: summary,
      anterior: previous,
    );
    final missing = summary.dadosAusentes.isEmpty
        ? ''
        : '\n\nNÃO TENHO DADOS SUFICIENTES para algumas conclusões:\n- ${summary.dadosAusentes.join('\n- ')}';
    final insightText = insights.isEmpty
        ? ''
        : '\n\nInsights:\n${insights.map((item) => '• ${item.explicacao}').join('\n')}';
    final answer =
        '''Faturamento: ${AppFormatters.moeda(summary.faturamento)}
Recebido: ${AppFormatters.moeda(summary.recebido)}
A receber: ${AppFormatters.moeda(summary.aReceber)}
Resultado estimado: ${AppFormatters.moeda(summary.resultado)}
Saldo realizado: ${AppFormatters.moeda(summary.saldoRealizado)}

Resultado considera competência, custos, comissões e despesas. Saldo realizado considera apenas dinheiro efetivamente recebido e pago.$insightText$missing''';
    return ManagementAnswer(texto: answer, resumo: summary, insights: insights);
  }
}
