enum StatusAgendamento {
  agendado,
  confirmado,
  emAtendimento,
  concluido,
  cancelado,
  faltou,
}

enum FormaPagamento {
  pix,
  dinheiro,
  cartaoCredito,
  cartaoDebito,
  transferencia,
  fiado,
}

class Agendamento {
  final String id;

  final String clienteId;
  final String profissionalId;
  final String servicoId;

  final DateTime inicio;
  final DateTime fim;

  final StatusAgendamento status;

  final FormaPagamento? formaPagamento;

  final double valorServico;
  final double desconto;
  final double valorRecebido;

  final bool confirmado;
  final bool compareceu;

  final String? observacoes;

  final String? consumoPrevistoJson;
  final String? consumoRealizadoJson;
  final bool estoqueConsumido;

  final DateTime dataCriacao;

  const Agendamento({
    required this.id,
    required this.clienteId,
    required this.profissionalId,
    required this.servicoId,
    required this.inicio,
    required this.fim,
    required this.valorServico,
    this.status = StatusAgendamento.agendado,
    this.formaPagamento,
    this.desconto = 0,
    this.valorRecebido = 0,
    this.confirmado = false,
    this.compareceu = false,
    this.observacoes,
    this.consumoPrevistoJson,
    this.consumoRealizadoJson,
    this.estoqueConsumido = false,
    required this.dataCriacao,
  });

  double get valorFinal {
    return valorServico - desconto;
  }

  Duration get duracao {
    return fim.difference(inicio);
  }

  bool get estaConcluido {
    return status == StatusAgendamento.concluido;
  }

  bool get estaCancelado {
    return status == StatusAgendamento.cancelado;
  }

  bool get estaEmAndamento {
    return status == StatusAgendamento.emAtendimento;
  }

  bool get estaConfirmado {
    return confirmado;
  }

  bool get pagamentoPendente {
    return valorRecebido < valorFinal;
  }

  double get valorRestante {
    return valorFinal - valorRecebido;
  }

  Agendamento copiarCom({
    StatusAgendamento? status,
    FormaPagamento? formaPagamento,
    double? desconto,
    double? valorRecebido,
    bool? confirmado,
    bool? compareceu,
    String? observacoes,
  }) {
    return Agendamento(
      id: id,
      clienteId: clienteId,
      profissionalId: profissionalId,
      servicoId: servicoId,
      inicio: inicio,
      fim: fim,
      valorServico: valorServico,
      status: status ?? this.status,
      formaPagamento: formaPagamento ?? this.formaPagamento,
      desconto: desconto ?? this.desconto,
      valorRecebido: valorRecebido ?? this.valorRecebido,
      confirmado: confirmado ?? this.confirmado,
      compareceu: compareceu ?? this.compareceu,
      observacoes: observacoes ?? this.observacoes,
      consumoPrevistoJson: consumoPrevistoJson,
      consumoRealizadoJson: consumoRealizadoJson,
      estoqueConsumido: estoqueConsumido,
      dataCriacao: dataCriacao,
    );
  }
}
