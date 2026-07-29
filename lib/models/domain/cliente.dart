class Cliente {
  final String id;
  final String nome;
  final String whatsapp;
  final String? telefone;
  final String? email;
  final DateTime? dataNascimento;

  final String? profissionalPrincipalId;
  final String? profissionalSecundariaId;

  final String? observacoes;
  final List<String> preferencias;
  final List<String> etiquetas;

  final bool ativo;
  final DateTime dataCadastro;
  final DateTime? ultimoAtendimento;

  final int totalAtendimentos;
  final double totalGasto;
  final int pontosFidelidade;

  final FichaAnamnese? fichaAnamnese;
  final List<ConsentimentoCliente> consentimentos;
  final List<FotoCliente> fotos;

  const Cliente({
    required this.id,
    required this.nome,
    required this.whatsapp,
    this.telefone,
    this.email,
    this.dataNascimento,
    this.profissionalPrincipalId,
    this.profissionalSecundariaId,
    this.observacoes,
    this.preferencias = const [],
    this.etiquetas = const [],
    this.ativo = true,
    required this.dataCadastro,
    this.ultimoAtendimento,
    this.totalAtendimentos = 0,
    this.totalGasto = 0,
    this.pontosFidelidade = 0,
    this.fichaAnamnese,
    this.consentimentos = const [],
    this.fotos = const [],
  });

  bool get possuiProfissionalPrincipal {
    return profissionalPrincipalId != null &&
        profissionalPrincipalId!.isNotEmpty;
  }

  bool get possuiAnamnese {
    return fichaAnamnese != null;
  }

  bool get fichaAnamneseDesatualizada {
    if (fichaAnamnese == null) {
      return true;
    }

    final diasDesdeAtualizacao = DateTime.now()
        .difference(fichaAnamnese!.dataAtualizacao)
        .inDays;

    return diasDesdeAtualizacao > 180;
  }

  bool get fazAniversarioHoje {
    if (dataNascimento == null) {
      return false;
    }

    final hoje = DateTime.now();

    return dataNascimento!.day == hoje.day &&
        dataNascimento!.month == hoje.month;
  }

  Cliente copiarCom({
    String? nome,
    String? whatsapp,
    String? telefone,
    String? email,
    DateTime? dataNascimento,
    String? profissionalPrincipalId,
    String? profissionalSecundariaId,
    String? observacoes,
    List<String>? preferencias,
    List<String>? etiquetas,
    bool? ativo,
    DateTime? ultimoAtendimento,
    int? totalAtendimentos,
    double? totalGasto,
    int? pontosFidelidade,
    FichaAnamnese? fichaAnamnese,
    List<ConsentimentoCliente>? consentimentos,
    List<FotoCliente>? fotos,
  }) {
    return Cliente(
      id: id,
      nome: nome ?? this.nome,
      whatsapp: whatsapp ?? this.whatsapp,
      telefone: telefone ?? this.telefone,
      email: email ?? this.email,
      dataNascimento: dataNascimento ?? this.dataNascimento,
      profissionalPrincipalId:
          profissionalPrincipalId ?? this.profissionalPrincipalId,
      profissionalSecundariaId:
          profissionalSecundariaId ?? this.profissionalSecundariaId,
      observacoes: observacoes ?? this.observacoes,
      preferencias: preferencias ?? this.preferencias,
      etiquetas: etiquetas ?? this.etiquetas,
      ativo: ativo ?? this.ativo,
      dataCadastro: dataCadastro,
      ultimoAtendimento: ultimoAtendimento ?? this.ultimoAtendimento,
      totalAtendimentos: totalAtendimentos ?? this.totalAtendimentos,
      totalGasto: totalGasto ?? this.totalGasto,
      pontosFidelidade: pontosFidelidade ?? this.pontosFidelidade,
      fichaAnamnese: fichaAnamnese ?? this.fichaAnamnese,
      consentimentos: consentimentos ?? this.consentimentos,
      fotos: fotos ?? this.fotos,
    );
  }
}

class FichaAnamnese {
  final String id;
  final String clienteId;
  final String tipoFicha;

  final bool possuiAlergias;
  final String? descricaoAlergias;

  final bool usaMedicamentos;
  final String? medicamentos;

  final bool possuiProblemasDePele;
  final String? problemasDePele;

  final bool possuiDiabetes;
  final bool possuiPressaoAlta;
  final bool estaGestante;
  final bool fezCirurgiaRecente;
  final bool usaAnticoagulante;
  final bool possuiSensibilidade;
  final bool usaAcidos;
  final bool possuiMicose;
  final bool possuiUnhaEncravada;
  final bool possuiSensibilidadeOcular;
  final bool usaLentesDeContato;
  final bool fezCirurgiaOcular;
  final bool possuiQuimicaNoCabelo;
  final bool possuiQuedaDeCabelo;

  final String? restricoes;
  final String? observacoes;

  final DateTime dataCriacao;
  final DateTime dataAtualizacao;

  final bool clienteConfirmouInformacoes;
  final String? assinaturaCliente;

  const FichaAnamnese({
    required this.id,
    required this.clienteId,
    required this.tipoFicha,
    this.possuiAlergias = false,
    this.descricaoAlergias,
    this.usaMedicamentos = false,
    this.medicamentos,
    this.possuiProblemasDePele = false,
    this.problemasDePele,
    this.possuiDiabetes = false,
    this.possuiPressaoAlta = false,
    this.estaGestante = false,
    this.fezCirurgiaRecente = false,
    this.usaAnticoagulante = false,
    this.possuiSensibilidade = false,
    this.usaAcidos = false,
    this.possuiMicose = false,
    this.possuiUnhaEncravada = false,
    this.possuiSensibilidadeOcular = false,
    this.usaLentesDeContato = false,
    this.fezCirurgiaOcular = false,
    this.possuiQuimicaNoCabelo = false,
    this.possuiQuedaDeCabelo = false,
    this.restricoes,
    this.observacoes,
    required this.dataCriacao,
    required this.dataAtualizacao,
    this.clienteConfirmouInformacoes = false,
    this.assinaturaCliente,
  });

  bool get possuiAlertaImportante {
    return possuiAlergias ||
        possuiDiabetes ||
        estaGestante ||
        usaAnticoagulante ||
        fezCirurgiaRecente ||
        possuiSensibilidadeOcular;
  }
}

class ConsentimentoCliente {
  final String id;
  final String clienteId;
  final String titulo;
  final String descricao;
  final DateTime dataAceite;
  final String? assinatura;
  final String? procedimentoId;
  final bool aceito;

  const ConsentimentoCliente({
    required this.id,
    required this.clienteId,
    required this.titulo,
    required this.descricao,
    required this.dataAceite,
    this.assinatura,
    this.procedimentoId,
    this.aceito = true,
  });
}

class FotoCliente {
  final String id;
  final String clienteId;
  final String caminhoArquivo;
  final String tipo;
  final String? descricao;
  final DateTime dataRegistro;
  final String? atendimentoId;

  const FotoCliente({
    required this.id,
    required this.clienteId,
    required this.caminhoArquivo,
    required this.tipo,
    this.descricao,
    required this.dataRegistro,
    this.atendimentoId,
  });
}
