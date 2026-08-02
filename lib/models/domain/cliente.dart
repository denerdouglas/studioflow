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

  final String? instagramUrl;
  final String? tiktokUrl;
  final String? facebookUrl;
  final String? websiteUrl;
  final String? avatarPathLocal;

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
    this.instagramUrl,
    this.tiktokUrl,
    this.facebookUrl,
    this.websiteUrl,
    this.avatarPathLocal,
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
    String? instagramUrl,
    String? tiktokUrl,
    String? facebookUrl,
    String? websiteUrl,
    String? avatarPathLocal,
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
      instagramUrl: instagramUrl ?? this.instagramUrl,
      tiktokUrl: tiktokUrl ?? this.tiktokUrl,
      facebookUrl: facebookUrl ?? this.facebookUrl,
      websiteUrl: websiteUrl ?? this.websiteUrl,
      avatarPathLocal: avatarPathLocal ?? this.avatarPathLocal,
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
  final String comercioId;
  final String clienteId;
  final String filePathLocal;
  final String? remoteUrl;
  final String thumbnailPath;
  final String? servicoId;
  final String? agendamentoId;
  final String? profissionalId;
  final String? atendimentoId;
  final String? vendaId;
  final String? descricao;
  final String categoria;
  final DateTime dataTrabalho;
  final DateTime criadoEm;
  final DateTime atualizadoEm;
  final int statusSincronizacao;
  final DateTime? excluidoEm;

  const FotoCliente({
    required this.id,
    required this.comercioId,
    required this.clienteId,
    required this.filePathLocal,
    this.remoteUrl,
    required this.thumbnailPath,
    this.servicoId,
    this.agendamentoId,
    this.profissionalId,
    this.atendimentoId,
    this.vendaId,
    this.descricao,
    required this.categoria,
    required this.dataTrabalho,
    required this.criadoEm,
    required this.atualizadoEm,
    this.statusSincronizacao = 0,
    this.excluidoEm,
  });

  Map<String, Object?> paraMapa() => {
        'id': id,
        'comercio_id': comercioId,
        'cliente_id': clienteId,
        'file_path_local': filePathLocal,
        'remote_url': remoteUrl,
        'thumbnail_path': thumbnailPath,
        'servico_id': servicoId,
        'agendamento_id': agendamentoId,
        'profissional_id': profissionalId,
        'atendimento_id': atendimentoId,
        'venda_id': vendaId,
        'descricao': descricao,
        'categoria': categoria,
        'data_trabalho': dataTrabalho.toIso8601String(),
        'criado_em': criadoEm.toIso8601String(),
        'atualizado_em': atualizadoEm.toIso8601String(),
        'status_sincronizacao': statusSincronizacao,
        'excluido_em': excluidoEm?.toIso8601String(),
      };

  factory FotoCliente.doMapa(Map<String, Object?> mapa) => FotoCliente(
        id: mapa['id'] as String,
        comercioId: mapa['comercio_id'] as String,
        clienteId: mapa['cliente_id'] as String,
        filePathLocal: mapa['file_path_local'] as String,
        remoteUrl: mapa['remote_url'] as String?,
        thumbnailPath: mapa['thumbnail_path'] as String,
        servicoId: mapa['servico_id'] as String?,
        agendamentoId: mapa['agendamento_id'] as String?,
        profissionalId: mapa['profissional_id'] as String?,
        atendimentoId: mapa['atendimento_id'] as String?,
        vendaId: mapa['venda_id'] as String?,
        descricao: mapa['descricao'] as String?,
        categoria: mapa['categoria'] as String,
        dataTrabalho: DateTime.parse(mapa['data_trabalho'] as String),
        criadoEm: DateTime.parse(mapa['criado_em'] as String),
        atualizadoEm: DateTime.parse(mapa['atualizado_em'] as String),
        statusSincronizacao: (mapa['status_sincronizacao'] as num? ?? 0).toInt(),
        excluidoEm: mapa['excluido_em'] != null
            ? DateTime.parse(mapa['excluido_em'] as String)
            : null,
      );
}
