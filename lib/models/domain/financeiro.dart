enum TipoMovimentacaoFinanceira {
  entrada,
  saida,
  comissao,
  sangria,
  aporte,
  ajuste,
}

enum FormaPagamentoFinanceira {
  pix,
  dinheiro,
  cartaoCredito,
  cartaoDebito,
  transferencia,
  boleto,
  outro,
}

enum StatusFinanceiro { pendente, pago, cancelado, estornado }

class MovimentacaoFinanceira {
  final String id;
  final TipoMovimentacaoFinanceira tipo;
  final String descricao;
  final double valor;

  final FormaPagamentoFinanceira? formaPagamento;
  final StatusFinanceiro status;

  final DateTime data;
  final DateTime dataCriacao;

  final String? categoria;
  final String? clienteId;
  final String? profissionalId;
  final String? agendamentoId;
  final String? servicoId;
  final String? usuarioResponsavelId;

  final String? observacoes;

  const MovimentacaoFinanceira({
    required this.id,
    required this.tipo,
    required this.descricao,
    required this.valor,
    this.formaPagamento,
    this.status = StatusFinanceiro.pago,
    required this.data,
    required this.dataCriacao,
    this.categoria,
    this.clienteId,
    this.profissionalId,
    this.agendamentoId,
    this.servicoId,
    this.usuarioResponsavelId,
    this.observacoes,
  });

  bool get eEntrada {
    return tipo == TipoMovimentacaoFinanceira.entrada ||
        tipo == TipoMovimentacaoFinanceira.aporte;
  }

  bool get eSaida {
    return tipo == TipoMovimentacaoFinanceira.saida ||
        tipo == TipoMovimentacaoFinanceira.comissao ||
        tipo == TipoMovimentacaoFinanceira.sangria;
  }

  bool get estaPago {
    return status == StatusFinanceiro.pago;
  }

  double get valorComSinal {
    if (eEntrada) {
      return valor;
    }

    if (eSaida) {
      return -valor;
    }

    return 0;
  }
}

class FechamentoCaixa {
  final String id;
  final DateTime data;

  final double saldoInicial;
  final double totalEntradas;
  final double totalSaidas;
  final double totalComissoes;
  final double totalSangrias;

  final double totalPix;
  final double totalDinheiro;
  final double totalCartaoCredito;
  final double totalCartaoDebito;
  final double totalTransferencia;

  final double saldoFinalInformado;
  final double saldoFinalCalculado;

  final String usuarioResponsavelId;
  final String? observacoes;

  final DateTime dataFechamento;
  final bool fechado;

  const FechamentoCaixa({
    required this.id,
    required this.data,
    required this.saldoInicial,
    required this.totalEntradas,
    required this.totalSaidas,
    required this.totalComissoes,
    required this.totalSangrias,
    required this.totalPix,
    required this.totalDinheiro,
    required this.totalCartaoCredito,
    required this.totalCartaoDebito,
    required this.totalTransferencia,
    required this.saldoFinalInformado,
    required this.saldoFinalCalculado,
    required this.usuarioResponsavelId,
    this.observacoes,
    required this.dataFechamento,
    this.fechado = true,
  });

  double get diferencaCaixa {
    return saldoFinalInformado - saldoFinalCalculado;
  }

  bool get caixaConfere {
    return diferencaCaixa.abs() < 0.01;
  }
}

class ContaFinanceira {
  final String id;
  final String titulo;
  final String categoria;

  final double valor;
  final DateTime vencimento;

  final bool contaPagar;
  final StatusFinanceiro status;

  final DateTime? dataPagamento;
  final FormaPagamentoFinanceira? formaPagamento;

  final bool recorrente;
  final String? recorrencia;

  final String? fornecedor;
  final String? observacoes;

  const ContaFinanceira({
    required this.id,
    required this.titulo,
    required this.categoria,
    required this.valor,
    required this.vencimento,
    required this.contaPagar,
    this.status = StatusFinanceiro.pendente,
    this.dataPagamento,
    this.formaPagamento,
    this.recorrente = false,
    this.recorrencia,
    this.fornecedor,
    this.observacoes,
  });

  bool get vencida {
    return status == StatusFinanceiro.pendente &&
        vencimento.isBefore(DateTime.now());
  }

  int get diasParaVencimento {
    return vencimento.difference(DateTime.now()).inDays;
  }

  bool get venceEmBreve {
    return status == StatusFinanceiro.pendente &&
        diasParaVencimento >= 0 &&
        diasParaVencimento <= 3;
  }
}

class ComissaoProfissional {
  final String id;
  final String profissionalId;
  final String agendamentoId;
  final String servicoId;

  final double valorServico;
  final double percentualComissao;
  final double valorComissao;

  final DateTime dataGeracao;
  final DateTime? dataPagamento;

  final StatusFinanceiro status;
  final String? observacoes;

  const ComissaoProfissional({
    required this.id,
    required this.profissionalId,
    required this.agendamentoId,
    required this.servicoId,
    required this.valorServico,
    required this.percentualComissao,
    required this.valorComissao,
    required this.dataGeracao,
    this.dataPagamento,
    this.status = StatusFinanceiro.pendente,
    this.observacoes,
  });

  bool get paga {
    return status == StatusFinanceiro.pago;
  }
}

class ResumoFinanceiro {
  final DateTime inicio;
  final DateTime fim;

  final double faturamentoBruto;
  final double descontos;
  final double despesas;
  final double comissoes;
  final double custoMateriais;

  final int totalAtendimentos;
  final int totalCancelamentos;
  final int totalFaltas;

  const ResumoFinanceiro({
    required this.inicio,
    required this.fim,
    required this.faturamentoBruto,
    required this.descontos,
    required this.despesas,
    required this.comissoes,
    required this.custoMateriais,
    required this.totalAtendimentos,
    required this.totalCancelamentos,
    required this.totalFaltas,
  });

  double get faturamentoLiquido {
    return faturamentoBruto - descontos;
  }

  double get lucroLiquido {
    return faturamentoLiquido - despesas - comissoes - custoMateriais;
  }

  double get ticketMedio {
    if (totalAtendimentos == 0) {
      return 0;
    }

    return faturamentoLiquido / totalAtendimentos;
  }

  double get taxaFaltas {
    final totalAgendamentos =
        totalAtendimentos + totalCancelamentos + totalFaltas;

    if (totalAgendamentos == 0) {
      return 0;
    }

    return (totalFaltas / totalAgendamentos) * 100;
  }
}
