class Servico {
  final String id;
  final String nome;
  final String categoria;
  final String? descricao;

  final double preco;
  final int duracaoMinutos;

  final bool ativo;

  final List<String> profissionaisIds;
  final List<ConsumoMaterial> materiaisUtilizados;

  final double? comissaoPercentualPadrao;
  final double? custoEstimado;

  const Servico({
    required this.id,
    required this.nome,
    required this.categoria,
    this.descricao,
    required this.preco,
    required this.duracaoMinutos,
    this.ativo = true,
    this.profissionaisIds = const [],
    this.materiaisUtilizados = const [],
    this.comissaoPercentualPadrao,
    this.custoEstimado,
  });

  double get lucroEstimado {
    return preco - (custoEstimado ?? 0);
  }

  bool profissionalPodeExecutar(String profissionalId) {
    return profissionaisIds.contains(profissionalId);
  }

  double calcularComissao({required double percentualPadraoProfissional}) {
    final percentual = comissaoPercentualPadrao ?? percentualPadraoProfissional;

    return preco * (percentual / 100);
  }

  int calcularHorarioFinalEmMinutos({
    required int horaInicio,
    required int minutoInicio,
  }) {
    final inicioEmMinutos = (horaInicio * 60) + minutoInicio;

    return inicioEmMinutos + duracaoMinutos;
  }

  Servico copiarCom({
    String? nome,
    String? categoria,
    String? descricao,
    double? preco,
    int? duracaoMinutos,
    bool? ativo,
    List<String>? profissionaisIds,
    List<ConsumoMaterial>? materiaisUtilizados,
    double? comissaoPercentualPadrao,
    double? custoEstimado,
  }) {
    return Servico(
      id: id,
      nome: nome ?? this.nome,
      categoria: categoria ?? this.categoria,
      descricao: descricao ?? this.descricao,
      preco: preco ?? this.preco,
      duracaoMinutos: duracaoMinutos ?? this.duracaoMinutos,
      ativo: ativo ?? this.ativo,
      profissionaisIds: profissionaisIds ?? this.profissionaisIds,
      materiaisUtilizados: materiaisUtilizados ?? this.materiaisUtilizados,
      comissaoPercentualPadrao:
          comissaoPercentualPadrao ?? this.comissaoPercentualPadrao,
      custoEstimado: custoEstimado ?? this.custoEstimado,
    );
  }
}

class ConsumoMaterial {
  final String produtoId;
  final double quantidade;
  final String unidade;

  const ConsumoMaterial({
    required this.produtoId,
    required this.quantidade,
    required this.unidade,
  });
}
