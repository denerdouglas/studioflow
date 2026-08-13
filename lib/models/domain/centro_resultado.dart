enum CentroResultado { geral, salao, loja, naoClassificado }

enum PeriodoGestaoTipo { hoje, seteDias, mes, mesAnterior, personalizado }

class PeriodoGestao {
  final DateTime inicio;
  final DateTime fimExclusivo;
  final PeriodoGestaoTipo tipo;

  const PeriodoGestao({
    required this.inicio,
    required this.fimExclusivo,
    required this.tipo,
  });

  factory PeriodoGestao.doTipo(PeriodoGestaoTipo tipo, {DateTime? agora}) {
    final now = agora ?? DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    return switch (tipo) {
      PeriodoGestaoTipo.hoje => PeriodoGestao(
        inicio: day,
        fimExclusivo: day.add(const Duration(days: 1)),
        tipo: tipo,
      ),
      PeriodoGestaoTipo.seteDias => PeriodoGestao(
        inicio: day.subtract(const Duration(days: 6)),
        fimExclusivo: day.add(const Duration(days: 1)),
        tipo: tipo,
      ),
      PeriodoGestaoTipo.mes => PeriodoGestao(
        inicio: DateTime(now.year, now.month),
        fimExclusivo: DateTime(now.year, now.month + 1),
        tipo: tipo,
      ),
      PeriodoGestaoTipo.mesAnterior => PeriodoGestao(
        inicio: DateTime(now.year, now.month - 1),
        fimExclusivo: DateTime(now.year, now.month),
        tipo: tipo,
      ),
      PeriodoGestaoTipo.personalizado => throw ArgumentError(
        'Informe as datas do período personalizado.',
      ),
    };
  }

  factory PeriodoGestao.personalizado(DateTime inicio, DateTime fimInclusivo) {
    final start = DateTime(inicio.year, inicio.month, inicio.day);
    final end = DateTime(
      fimInclusivo.year,
      fimInclusivo.month,
      fimInclusivo.day,
    ).add(const Duration(days: 1));
    if (!end.isAfter(start)) throw ArgumentError('Período inválido.');
    return PeriodoGestao(
      inicio: start,
      fimExclusivo: end,
      tipo: PeriodoGestaoTipo.personalizado,
    );
  }
}

class ResumoCentroResultado {
  final CentroResultado centro;
  final PeriodoGestao periodo;
  final double faturamento;
  final double recebido;
  final double aReceber;
  final double custosConhecidos;
  final double comissoes;
  final double despesas;
  final double resultado;
  final double saldoRealizado;
  final double ticketMedio;
  final int quantidadeVendas;
  final int servicosRealizados;
  final double salao;
  final double loja;
  final double administrativo;
  final double naoClassificado;
  final int registros;
  final List<String> fontes;
  final List<String> dadosAusentes;
  final List<String> premissas;

  const ResumoCentroResultado({
    required this.centro,
    required this.periodo,
    required this.faturamento,
    required this.recebido,
    required this.aReceber,
    required this.custosConhecidos,
    required this.comissoes,
    required this.despesas,
    required this.resultado,
    required this.saldoRealizado,
    required this.ticketMedio,
    required this.quantidadeVendas,
    required this.servicosRealizados,
    this.salao = 0,
    this.loja = 0,
    this.administrativo = 0,
    this.naoClassificado = 0,
    this.registros = 0,
    this.fontes = const [],
    this.dadosAusentes = const [],
    this.premissas = const [],
  });
}

class DetalheCentroResultado {
  final String id;
  final String titulo;
  final double valor;
  final DateTime data;
  final CentroResultado centro;
  final String fonte;
  final String? entidadeId;
  final String status;

  const DetalheCentroResultado({
    required this.id,
    required this.titulo,
    required this.valor,
    required this.data,
    required this.centro,
    required this.fonte,
    required this.status,
    this.entidadeId,
  });
}
