class Profissional {
  final String id;
  final String nome;
  final String whatsapp;
  final String? email;
  final String cargo;
  final String? fotoPerfil;

  final bool ativo;

  final List<String> servicosIds;
  final List<String> clientesVinculadosIds;

  final double percentualComissaoPadrao;
  final Map<String, double> comissaoPorServico;

  final double metaMensal;
  final double faturamentoMesAtual;

  final List<HorarioDisponivel> horariosDisponiveis;
  final List<BloqueioAgenda> bloqueiosAgenda;

  const Profissional({
    required this.id,
    required this.nome,
    required this.whatsapp,
    this.email,
    required this.cargo,
    this.fotoPerfil,
    this.ativo = true,
    this.servicosIds = const [],
    this.clientesVinculadosIds = const [],
    this.percentualComissaoPadrao = 50,
    this.comissaoPorServico = const {},
    this.metaMensal = 0,
    this.faturamentoMesAtual = 0,
    this.horariosDisponiveis = const [],
    this.bloqueiosAgenda = const [],
  });

  double get percentualMetaAtingida {
    if (metaMensal <= 0) {
      return 0;
    }

    return (faturamentoMesAtual / metaMensal) * 100;
  }

  double get valorRestanteMeta {
    final restante = metaMensal - faturamentoMesAtual;

    if (restante < 0) {
      return 0;
    }

    return restante;
  }

  double calcularComissao({
    required String servicoId,
    required double valorServico,
  }) {
    final percentual =
        comissaoPorServico[servicoId] ?? percentualComissaoPadrao;

    return valorServico * (percentual / 100);
  }

  bool atendeCliente(String clienteId) {
    return clientesVinculadosIds.contains(clienteId);
  }

  bool realizaServico(String servicoId) {
    return servicosIds.contains(servicoId);
  }

  Profissional copiarCom({
    String? nome,
    String? whatsapp,
    String? email,
    String? cargo,
    String? fotoPerfil,
    bool? ativo,
    List<String>? servicosIds,
    List<String>? clientesVinculadosIds,
    double? percentualComissaoPadrao,
    Map<String, double>? comissaoPorServico,
    double? metaMensal,
    double? faturamentoMesAtual,
    List<HorarioDisponivel>? horariosDisponiveis,
    List<BloqueioAgenda>? bloqueiosAgenda,
  }) {
    return Profissional(
      id: id,
      nome: nome ?? this.nome,
      whatsapp: whatsapp ?? this.whatsapp,
      email: email ?? this.email,
      cargo: cargo ?? this.cargo,
      fotoPerfil: fotoPerfil ?? this.fotoPerfil,
      ativo: ativo ?? this.ativo,
      servicosIds: servicosIds ?? this.servicosIds,
      clientesVinculadosIds:
          clientesVinculadosIds ?? this.clientesVinculadosIds,
      percentualComissaoPadrao:
          percentualComissaoPadrao ?? this.percentualComissaoPadrao,
      comissaoPorServico: comissaoPorServico ?? this.comissaoPorServico,
      metaMensal: metaMensal ?? this.metaMensal,
      faturamentoMesAtual: faturamentoMesAtual ?? this.faturamentoMesAtual,
      horariosDisponiveis: horariosDisponiveis ?? this.horariosDisponiveis,
      bloqueiosAgenda: bloqueiosAgenda ?? this.bloqueiosAgenda,
    );
  }
}

class HorarioDisponivel {
  final int diaSemana;
  final String horarioInicio;
  final String horarioFim;
  final String? intervaloInicio;
  final String? intervaloFim;
  final bool disponivel;

  const HorarioDisponivel({
    required this.diaSemana,
    required this.horarioInicio,
    required this.horarioFim,
    this.intervaloInicio,
    this.intervaloFim,
    this.disponivel = true,
  });
}

class BloqueioAgenda {
  final String id;
  final DateTime dataInicio;
  final DateTime dataFim;
  final String motivo;
  final bool diaInteiro;

  const BloqueioAgenda({
    required this.id,
    required this.dataInicio,
    required this.dataFim,
    required this.motivo,
    this.diaInteiro = false,
  });
}
