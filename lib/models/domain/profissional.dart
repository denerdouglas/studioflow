class Profissional {
  final String id;
  final String nome;
  final String whatsapp;
  final String? email;
  final String cargo;
  final String? fotoPerfil;

  final String? documento; // CPF ou outro
  final String? rg;
  final String? dataNascimento;
  final String? chavePix;
  final String? banco;
  final String? corAgenda;
  final String? unidadeId;
  final String? sexo;
  final String? observacoes;
  final String? contatoEmergencia;

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
    this.documento,
    this.rg,
    this.dataNascimento,
    this.chavePix,
    this.banco,
    this.corAgenda,
    this.unidadeId,
    this.sexo,
    this.observacoes,
    this.contatoEmergencia,
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
    String? documento,
    String? rg,
    String? dataNascimento,
    String? chavePix,
    String? banco,
    String? corAgenda,
    String? unidadeId,
    String? sexo,
    String? observacoes,
    String? contatoEmergencia,
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
      documento: documento ?? this.documento,
      rg: rg ?? this.rg,
      dataNascimento: dataNascimento ?? this.dataNascimento,
      chavePix: chavePix ?? this.chavePix,
      banco: banco ?? this.banco,
      corAgenda: corAgenda ?? this.corAgenda,
      unidadeId: unidadeId ?? this.unidadeId,
      sexo: sexo ?? this.sexo,
      observacoes: observacoes ?? this.observacoes,
      contatoEmergencia: contatoEmergencia ?? this.contatoEmergencia,
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
