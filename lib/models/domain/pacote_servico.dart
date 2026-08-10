enum TipoSequenciaPacote { livre, obrigatoria }

enum RegraFaltaPacote { manter, consumir, parcial, aprovar }

enum ModoComissaoPacote { venda, porSessao, dividida }

enum FrequenciaAgendamentoPacote { dias, semanal, mensal }

enum EscopoReagendamentoPacote { somenteEsta, estaEProximas, refazerRestante }

class PacoteItemEntrada {
  final String servicoId;
  final int quantidade;
  final int? ordemInicial;
  final int intervaloMinimoDias;
  final int? intervaloMaximoDias;
  final int? duracaoMinutos;
  final List<String> profissionaisAutorizados;

  const PacoteItemEntrada({
    required this.servicoId,
    required this.quantidade,
    this.ordemInicial,
    this.intervaloMinimoDias = 0,
    this.intervaloMaximoDias,
    this.duracaoMinutos,
    this.profissionaisAutorizados = const [],
  });
}

class PacoteEntrada {
  final String? id;
  final String nome;
  final String descricao;
  final String categoria;
  final List<PacoteItemEntrada> itens;
  final TipoSequenciaPacote tipoSequencia;
  final double precoPacote;
  final int validadeDias;
  final int intervaloRecomendadoDias;
  final String formaPagamentoPadrao;
  final bool permiteParcelamento;
  final int maxParcelas;
  final bool exigeSinal;
  final double sinalPadrao;
  final String regrasCancelamento;
  final RegraFaltaPacote regraFalta;
  final double percentualFalta;
  final bool permiteTransferencia;
  final ModoComissaoPacote modoComissao;
  final double percentualVendedor;
  final String observacoes;
  final bool ativo;

  const PacoteEntrada({
    this.id,
    required this.nome,
    this.descricao = '',
    required this.categoria,
    required this.itens,
    this.tipoSequencia = TipoSequenciaPacote.livre,
    required this.precoPacote,
    required this.validadeDias,
    this.intervaloRecomendadoDias = 7,
    this.formaPagamentoPadrao = 'Pix',
    this.permiteParcelamento = false,
    this.maxParcelas = 1,
    this.exigeSinal = false,
    this.sinalPadrao = 0,
    this.regrasCancelamento = '',
    this.regraFalta = RegraFaltaPacote.manter,
    this.percentualFalta = 0,
    this.permiteTransferencia = false,
    this.modoComissao = ModoComissaoPacote.porSessao,
    this.percentualVendedor = 0,
    this.observacoes = '',
    this.ativo = true,
  });
}

class VendaPacoteEntrada {
  final String pacoteId;
  final String clienteId;
  final String vendedorProfissionalId;
  final double desconto;
  final double sinal;
  final double valorPagoInicial;
  final int parcelas;
  final String formaPagamento;
  final DateTime dataCompra;
  final String? comandaReferencia;

  const VendaPacoteEntrada({
    required this.pacoteId,
    required this.clienteId,
    required this.vendedorProfissionalId,
    this.desconto = 0,
    this.sinal = 0,
    this.valorPagoInicial = 0,
    this.parcelas = 1,
    required this.formaPagamento,
    required this.dataCompra,
    this.comandaReferencia,
  });
}

class SolicitacaoAgendaPacote {
  final String vendaId;
  final DateTime primeiraData;
  final Set<int> diasSemana;
  final int horaPreferida;
  final int minutoPreferido;
  final String profissionalId;
  final FrequenciaAgendamentoPacote frequencia;
  final int intervalo;
  final int limiteBuscaDias;

  const SolicitacaoAgendaPacote({
    required this.vendaId,
    required this.primeiraData,
    required this.diasSemana,
    required this.horaPreferida,
    required this.minutoPreferido,
    required this.profissionalId,
    this.frequencia = FrequenciaAgendamentoPacote.semanal,
    this.intervalo = 1,
    this.limiteBuscaDias = 180,
  });
}

class SessaoPlanejadaPacote {
  final String sessaoId;
  final String servicoId;
  final String servicoNome;
  final String profissionalId;
  final String profissionalNome;
  final DateTime inicio;
  final int duracaoMinutos;
  final bool horarioAlternativo;
  final String? aviso;

  const SessaoPlanejadaPacote({
    required this.sessaoId,
    required this.servicoId,
    required this.servicoNome,
    required this.profissionalId,
    required this.profissionalNome,
    required this.inicio,
    required this.duracaoMinutos,
    required this.horarioAlternativo,
    this.aviso,
  });

  DateTime get fim => inicio.add(Duration(minutes: duracaoMinutos));

  SessaoPlanejadaPacote copyWith({
    String? sessaoId,
    String? servicoId,
    String? servicoNome,
    String? profissionalId,
    String? profissionalNome,
    DateTime? inicio,
    int? duracaoMinutos,
    bool? horarioAlternativo,
    String? aviso,
  }) {
    return SessaoPlanejadaPacote(
      sessaoId: sessaoId ?? this.sessaoId,
      servicoId: servicoId ?? this.servicoId,
      servicoNome: servicoNome ?? this.servicoNome,
      profissionalId: profissionalId ?? this.profissionalId,
      profissionalNome: profissionalNome ?? this.profissionalNome,
      inicio: inicio ?? this.inicio,
      duracaoMinutos: duracaoMinutos ?? this.duracaoMinutos,
      horarioAlternativo: horarioAlternativo ?? this.horarioAlternativo,
      aviso: aviso ?? this.aviso,
    );
  }
}

class PreviaAgendaPacote {
  final List<SessaoPlanejadaPacote> sessoes;
  final List<String> naoEncaixadas;

  const PreviaAgendaPacote({
    required this.sessoes,
    required this.naoEncaixadas,
  });

  bool get completa => naoEncaixadas.isEmpty;

  PreviaAgendaPacote copyWith({
    List<SessaoPlanejadaPacote>? sessoes,
    List<String>? naoEncaixadas,
  }) {
    return PreviaAgendaPacote(
      sessoes: sessoes ?? this.sessoes,
      naoEncaixadas: naoEncaixadas ?? this.naoEncaixadas,
    );
  }
}

class ResumoVendaPacote {
  final String id;
  final String pacoteNome;
  final String clienteNome;
  final double valorContratado;
  final double valorPago;
  final double valorPendente;
  final int contratadas;
  final int realizadas;
  final int agendadas;
  final int disponiveis;
  final int canceladas;
  final int vencidas;
  final DateTime validade;
  final String status;

  const ResumoVendaPacote({
    required this.id,
    required this.pacoteNome,
    required this.clienteNome,
    required this.valorContratado,
    required this.valorPago,
    required this.valorPendente,
    required this.contratadas,
    required this.realizadas,
    required this.agendadas,
    required this.disponiveis,
    required this.canceladas,
    required this.vencidas,
    required this.validade,
    required this.status,
  });

  double get progresso => contratadas == 0 ? 0 : realizadas / contratadas;
}

class PacoteItemRegistro {
  final String id;
  final String servicoId;
  final String servicoNome;
  final int quantidadeSessoes;
  final int? ordem;

  const PacoteItemRegistro({
    required this.id,
    required this.servicoId,
    required this.servicoNome,
    required this.quantidadeSessoes,
    this.ordem,
  });
}

class PacoteModeloRegistro {
  final String id;
  final String nome;
  final double preco;
  final int? validadeDias;
  final String regrasUso;
  final bool ativo;
  final String itensResumo;
  final int totalSessoes;

  const PacoteModeloRegistro({
    required this.id,
    required this.nome,
    required this.preco,
    this.validadeDias,
    required this.regrasUso,
    required this.ativo,
    required this.itensResumo,
    required this.totalSessoes,
  });
}

class SessaoDisponivelRegistro {
  final String sessaoId;
  final String pacoteNome;
  final String servicoId;
  final String servicoNome;
  final String pacoteVendidoId;
  final int duracaoMinutos;

  const SessaoDisponivelRegistro({
    required this.sessaoId,
    required this.pacoteNome,
    required this.servicoId,
    required this.servicoNome,
    required this.pacoteVendidoId,
    required this.duracaoMinutos,
  });
}
