enum TipoItemEstoque { produto, materialDescartavel, equipamento, ferramenta }

enum TipoMovimentacaoEstoque { entrada, consumo, perda, ajuste, devolucao }

class ItemEstoque {
  final String id;
  final String nome;
  final String categoria;
  final TipoItemEstoque tipo;

  final double quantidadeAtual;
  final double estoqueMinimo;
  final String unidade;
  final double conteudoPorUnidade;
  final String unidadeConteudo;
  final bool revisaoModelagemEstoque;

  final double custoUnitario;
  final String? fornecedor;
  final String? codigoBarras;

  final DateTime? dataValidade;
  final DateTime dataCadastro;

  final bool ativo;
  final bool descontarAutomaticamente;

  final String? observacoes;

  const ItemEstoque({
    required this.id,
    required this.nome,
    required this.categoria,
    required this.tipo,
    required this.quantidadeAtual,
    required this.estoqueMinimo,
    required this.unidade,
    this.conteudoPorUnidade = 1,
    this.unidadeConteudo = '',
    this.revisaoModelagemEstoque = false,
    required this.custoUnitario,
    this.fornecedor,
    this.codigoBarras,
    this.dataValidade,
    required this.dataCadastro,
    this.ativo = true,
    this.descontarAutomaticamente = true,
    this.observacoes,
  });

  bool get estoqueBaixo {
    return quantidadeAtual <= estoqueMinimo;
  }

  bool get semEstoque {
    return quantidadeAtual <= 0;
  }

  bool get possuiValidade {
    return dataValidade != null;
  }

  bool get validadeProxima {
    if (dataValidade == null) {
      return false;
    }

    final diasRestantes = dataValidade!.difference(DateTime.now()).inDays;

    return diasRestantes <= 30;
  }

  bool get vencido {
    if (dataValidade == null) {
      return false;
    }

    return dataValidade!.isBefore(DateTime.now());
  }

  double get valorTotalEmEstoque {
    return quantidadeAtual * custoUnitario;
  }

  double get quantidadeParaReposicao {
    if (!estoqueBaixo) {
      return 0;
    }

    final quantidadeIdeal = estoqueMinimo * 2;
    final reposicao = quantidadeIdeal - quantidadeAtual;

    return reposicao > 0 ? reposicao : 0;
  }

  ItemEstoque copiarCom({
    String? nome,
    String? categoria,
    TipoItemEstoque? tipo,
    double? quantidadeAtual,
    double? estoqueMinimo,
    String? unidade,
    double? conteudoPorUnidade,
    String? unidadeConteudo,
    bool? revisaoModelagemEstoque,
    double? custoUnitario,
    String? fornecedor,
    String? codigoBarras,
    DateTime? dataValidade,
    bool? ativo,
    bool? descontarAutomaticamente,
    String? observacoes,
  }) {
    return ItemEstoque(
      id: id,
      nome: nome ?? this.nome,
      categoria: categoria ?? this.categoria,
      tipo: tipo ?? this.tipo,
      quantidadeAtual: quantidadeAtual ?? this.quantidadeAtual,
      estoqueMinimo: estoqueMinimo ?? this.estoqueMinimo,
      unidade: unidade ?? this.unidade,
      conteudoPorUnidade: conteudoPorUnidade ?? this.conteudoPorUnidade,
      unidadeConteudo: unidadeConteudo ?? this.unidadeConteudo,
      revisaoModelagemEstoque:
          revisaoModelagemEstoque ?? this.revisaoModelagemEstoque,
      custoUnitario: custoUnitario ?? this.custoUnitario,
      fornecedor: fornecedor ?? this.fornecedor,
      codigoBarras: codigoBarras ?? this.codigoBarras,
      dataValidade: dataValidade ?? this.dataValidade,
      dataCadastro: dataCadastro,
      ativo: ativo ?? this.ativo,
      descontarAutomaticamente:
          descontarAutomaticamente ?? this.descontarAutomaticamente,
      observacoes: observacoes ?? this.observacoes,
    );
  }
}

class MovimentacaoEstoque {
  final String id;
  final String itemEstoqueId;
  final TipoMovimentacaoEstoque tipo;

  final double quantidade;
  final double quantidadeAnterior;
  final double quantidadePosterior;

  final DateTime data;
  final String? motivo;
  final String? atendimentoId;
  final String? profissionalId;
  final String? usuarioResponsavelId;

  const MovimentacaoEstoque({
    required this.id,
    required this.itemEstoqueId,
    required this.tipo,
    required this.quantidade,
    required this.quantidadeAnterior,
    required this.quantidadePosterior,
    required this.data,
    this.motivo,
    this.atendimentoId,
    this.profissionalId,
    this.usuarioResponsavelId,
  });
}

class ItemListaCompras {
  final String id;
  final String itemEstoqueId;
  final String nomeItem;

  final double quantidadeSugerida;
  final String unidade;

  final bool comprado;
  final DateTime dataInclusao;
  final DateTime? dataCompra;

  final String? fornecedor;
  final String? observacoes;

  const ItemListaCompras({
    required this.id,
    required this.itemEstoqueId,
    required this.nomeItem,
    required this.quantidadeSugerida,
    required this.unidade,
    this.comprado = false,
    required this.dataInclusao,
    this.dataCompra,
    this.fornecedor,
    this.observacoes,
  });
}

enum TipoManutencao {
  afiacao,
  esterilizacao,
  revisao,
  limpeza,
  troca,
  calibracao,
  outro,
}

enum StatusManutencao { programada, proxima, atrasada, concluida, cancelada }

class ManutencaoItem {
  final String id;
  final String itemEstoqueId;
  final String nomeItem;

  final TipoManutencao tipo;
  final StatusManutencao status;

  final DateTime dataProgramada;
  final DateTime? dataConclusao;

  final int diasAvisoAntecipado;

  final double? custo;
  final String? prestador;
  final String? observacoes;

  const ManutencaoItem({
    required this.id,
    required this.itemEstoqueId,
    required this.nomeItem,
    required this.tipo,
    required this.status,
    required this.dataProgramada,
    this.dataConclusao,
    this.diasAvisoAntecipado = 2,
    this.custo,
    this.prestador,
    this.observacoes,
  });

  int get diasRestantes {
    return dataProgramada.difference(DateTime.now()).inDays;
  }

  bool get precisaNotificar {
    if (status == StatusManutencao.concluida ||
        status == StatusManutencao.cancelada) {
      return false;
    }

    return diasRestantes <= diasAvisoAntecipado;
  }

  bool get atrasada {
    return dataProgramada.isBefore(DateTime.now()) &&
        status != StatusManutencao.concluida;
  }

  String get mensagemAlerta {
    if (atrasada) {
      return 'A manutenção de $nomeItem está atrasada.';
    }

    if (diasRestantes == 0) {
      return 'A manutenção de $nomeItem está programada para hoje.';
    }

    if (diasRestantes == 1) {
      return 'A manutenção de $nomeItem está programada para amanhã.';
    }

    return 'A manutenção de $nomeItem está programada para daqui a $diasRestantes dias.';
  }
}
