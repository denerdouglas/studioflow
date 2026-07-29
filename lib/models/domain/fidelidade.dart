enum TipoBeneficio {
  pontos,
  cashback,
  desconto,
  servicoGratis,
  brinde,
  cupom,
  clubeVantagens,
}

enum TipoMovimentacaoFidelidade {
  ganho,
  resgate,
  ajuste,
  expiracao,
  cancelamento,
}

enum NivelFidelidade { iniciante, bronze, prata, ouro, diamante }

extension NivelFidelidadeDados on NivelFidelidade {
  String get nome {
    switch (this) {
      case NivelFidelidade.iniciante:
        return 'Iniciante';
      case NivelFidelidade.bronze:
        return 'Bronze';
      case NivelFidelidade.prata:
        return 'Prata';
      case NivelFidelidade.ouro:
        return 'Ouro';
      case NivelFidelidade.diamante:
        return 'Diamante';
    }
  }

  int get pontosMinimos {
    switch (this) {
      case NivelFidelidade.iniciante:
        return 0;
      case NivelFidelidade.bronze:
        return 200;
      case NivelFidelidade.prata:
        return 500;
      case NivelFidelidade.ouro:
        return 1000;
      case NivelFidelidade.diamante:
        return 2000;
    }
  }

  double get percentualBonus {
    switch (this) {
      case NivelFidelidade.iniciante:
        return 0;
      case NivelFidelidade.bronze:
        return 5;
      case NivelFidelidade.prata:
        return 10;
      case NivelFidelidade.ouro:
        return 15;
      case NivelFidelidade.diamante:
        return 20;
    }
  }
}

class ProgramaFidelidade {
  final String id;
  final String nome;
  final String descricao;

  final bool ativo;

  final double pontosPorReal;
  final double valorMinimoParaPontuar;

  final bool possuiCashback;
  final double percentualCashback;

  final int diasValidadePontos;
  final int diasValidadeCashback;

  final List<RegraFidelidade> regras;
  final List<RecompensaFidelidade> recompensas;

  const ProgramaFidelidade({
    required this.id,
    required this.nome,
    required this.descricao,
    this.ativo = true,
    this.pontosPorReal = 1,
    this.valorMinimoParaPontuar = 0,
    this.possuiCashback = false,
    this.percentualCashback = 0,
    this.diasValidadePontos = 365,
    this.diasValidadeCashback = 90,
    this.regras = const [],
    this.recompensas = const [],
  });

  int calcularPontos(double valorGasto) {
    if (!ativo || valorGasto < valorMinimoParaPontuar) {
      return 0;
    }

    return (valorGasto * pontosPorReal).floor();
  }

  double calcularCashback(double valorGasto) {
    if (!ativo || !possuiCashback) {
      return 0;
    }

    return valorGasto * (percentualCashback / 100);
  }
}

class RegraFidelidade {
  final String id;
  final String titulo;
  final String descricao;

  final int? pontosExtras;
  final double? cashbackExtra;

  final String? servicoId;
  final String? profissionalId;

  final DateTime? dataInicio;
  final DateTime? dataFim;

  final bool ativa;

  const RegraFidelidade({
    required this.id,
    required this.titulo,
    required this.descricao,
    this.pontosExtras,
    this.cashbackExtra,
    this.servicoId,
    this.profissionalId,
    this.dataInicio,
    this.dataFim,
    this.ativa = true,
  });

  bool get vigente {
    if (!ativa) {
      return false;
    }

    final agora = DateTime.now();

    if (dataInicio != null && agora.isBefore(dataInicio!)) {
      return false;
    }

    if (dataFim != null && agora.isAfter(dataFim!)) {
      return false;
    }

    return true;
  }
}

class RecompensaFidelidade {
  final String id;
  final String titulo;
  final String descricao;

  final TipoBeneficio tipo;

  final int pontosNecessarios;
  final double? valorDesconto;
  final double? percentualDesconto;

  final String? servicoId;
  final String? produtoId;

  final int? limiteResgates;
  final DateTime? validade;

  final bool ativa;

  const RecompensaFidelidade({
    required this.id,
    required this.titulo,
    required this.descricao,
    required this.tipo,
    required this.pontosNecessarios,
    this.valorDesconto,
    this.percentualDesconto,
    this.servicoId,
    this.produtoId,
    this.limiteResgates,
    this.validade,
    this.ativa = true,
  });

  bool get disponivel {
    if (!ativa) {
      return false;
    }

    if (validade == null) {
      return true;
    }

    return validade!.isAfter(DateTime.now());
  }
}

class CarteiraFidelidadeCliente {
  final String clienteId;

  final int pontosDisponiveis;
  final int pontosAcumulados;
  final int pontosResgatados;
  final int pontosExpirados;

  final double cashbackDisponivel;
  final double cashbackAcumulado;
  final double cashbackUtilizado;

  final NivelFidelidade nivel;

  final DateTime ultimaAtualizacao;

  const CarteiraFidelidadeCliente({
    required this.clienteId,
    this.pontosDisponiveis = 0,
    this.pontosAcumulados = 0,
    this.pontosResgatados = 0,
    this.pontosExpirados = 0,
    this.cashbackDisponivel = 0,
    this.cashbackAcumulado = 0,
    this.cashbackUtilizado = 0,
    this.nivel = NivelFidelidade.iniciante,
    required this.ultimaAtualizacao,
  });

  bool podeResgatar(int pontosNecessarios) {
    return pontosDisponiveis >= pontosNecessarios;
  }

  bool podeUsarCashback(double valor) {
    return cashbackDisponivel >= valor;
  }

  NivelFidelidade calcularNivel() {
    if (pontosAcumulados >= NivelFidelidade.diamante.pontosMinimos) {
      return NivelFidelidade.diamante;
    }

    if (pontosAcumulados >= NivelFidelidade.ouro.pontosMinimos) {
      return NivelFidelidade.ouro;
    }

    if (pontosAcumulados >= NivelFidelidade.prata.pontosMinimos) {
      return NivelFidelidade.prata;
    }

    if (pontosAcumulados >= NivelFidelidade.bronze.pontosMinimos) {
      return NivelFidelidade.bronze;
    }

    return NivelFidelidade.iniciante;
  }
}

class MovimentacaoFidelidade {
  final String id;
  final String clienteId;

  final TipoMovimentacaoFidelidade tipo;

  final int pontos;
  final double cashback;

  final String descricao;

  final String? agendamentoId;
  final String? recompensaId;

  final DateTime dataMovimentacao;
  final DateTime? dataExpiracao;

  const MovimentacaoFidelidade({
    required this.id,
    required this.clienteId,
    required this.tipo,
    this.pontos = 0,
    this.cashback = 0,
    required this.descricao,
    this.agendamentoId,
    this.recompensaId,
    required this.dataMovimentacao,
    this.dataExpiracao,
  });

  bool get expirou {
    if (dataExpiracao == null) {
      return false;
    }

    return dataExpiracao!.isBefore(DateTime.now());
  }
}

class CupomDesconto {
  final String id;
  final String codigo;
  final String titulo;
  final String descricao;

  final double? valorDesconto;
  final double? percentualDesconto;

  final double? valorMinimoCompra;

  final DateTime dataInicio;
  final DateTime dataFim;

  final int limiteTotalUso;
  final int limiteUsoPorCliente;
  final int totalUtilizado;

  final List<String> servicosPermitidosIds;
  final List<String> clientesPermitidosIds;

  final bool ativo;

  const CupomDesconto({
    required this.id,
    required this.codigo,
    required this.titulo,
    required this.descricao,
    this.valorDesconto,
    this.percentualDesconto,
    this.valorMinimoCompra,
    required this.dataInicio,
    required this.dataFim,
    this.limiteTotalUso = 0,
    this.limiteUsoPorCliente = 1,
    this.totalUtilizado = 0,
    this.servicosPermitidosIds = const [],
    this.clientesPermitidosIds = const [],
    this.ativo = true,
  });

  bool get valido {
    final agora = DateTime.now();

    if (!ativo) {
      return false;
    }

    if (agora.isBefore(dataInicio) || agora.isAfter(dataFim)) {
      return false;
    }

    if (limiteTotalUso > 0 && totalUtilizado >= limiteTotalUso) {
      return false;
    }

    return true;
  }

  double calcularDesconto(double valorCompra) {
    if (!valido) {
      return 0;
    }

    if (valorMinimoCompra != null && valorCompra < valorMinimoCompra!) {
      return 0;
    }

    if (valorDesconto != null) {
      return valorDesconto! > valorCompra ? valorCompra : valorDesconto!;
    }

    if (percentualDesconto != null) {
      return valorCompra * (percentualDesconto! / 100);
    }

    return 0;
  }
}
