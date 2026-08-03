class ConfiguracaoComercio {
  final String comercioId;
  final String nomeComercio;
  final String nomeExibicao;
  final String telefone;
  final String whatsapp;
  final String endereco;
  final String chavePix;
  final String horarioAbertura;
  final String horarioFechamento;
  final Set<int> diasFuncionamento;
  final int duracaoPadraoMinutos;
  final bool notificacoesAtivas;
  final bool confirmarExclusoes;
  final bool permitirGaleriaClientes;
  final String? documentoTipo;
  final String? documento;
  final String? inscricaoEstadual;
  final String? instagram;
  final String? cep;
  final String? numero;
  final String? complemento;
  final String? bairro;
  final String? cidade;
  final String? estado;
  final String? capaUrl;
  final String? logoPath;
  final String? corPrincipal;
  final String? corSecundaria;
  final String? corDestaque;
  final String? temaModo;
  final bool? temaAutomatico;

  const ConfiguracaoComercio({
    required this.comercioId,
    required this.nomeComercio,
    required this.nomeExibicao,
    required this.telefone,
    required this.whatsapp,
    required this.endereco,
    required this.chavePix,
    required this.horarioAbertura,
    required this.horarioFechamento,
    required this.diasFuncionamento,
    required this.duracaoPadraoMinutos,
    required this.notificacoesAtivas,
    required this.confirmarExclusoes,
    this.permitirGaleriaClientes = false,
    this.documentoTipo,
    this.documento,
    this.inscricaoEstadual,
    this.instagram,
    this.cep,
    this.numero,
    this.complemento,
    this.bairro,
    this.cidade,
    this.estado,
    this.capaUrl,
    this.logoPath,
    this.corPrincipal,
    this.corSecundaria,
    this.corDestaque,
    this.temaModo,
    this.temaAutomatico,
  });

  String get moeda => 'BRL';

  ConfiguracaoComercio copiarCom({
    String? nomeComercio,
    String? nomeExibicao,
    String? telefone,
    String? whatsapp,
    String? endereco,
    String? chavePix,
    String? horarioAbertura,
    String? horarioFechamento,
    Set<int>? diasFuncionamento,
    int? duracaoPadraoMinutos,
    bool? notificacoesAtivas,
    bool? confirmarExclusoes,
    bool? permitirGaleriaClientes,
    String? documentoTipo,
    String? documento,
    String? inscricaoEstadual,
    String? instagram,
    String? cep,
    String? numero,
    String? complemento,
    String? bairro,
    String? cidade,
    String? estado,
    String? capaUrl,
    String? logoPath,
    String? corPrincipal,
    String? corSecundaria,
    String? corDestaque,
    String? temaModo,
    bool? temaAutomatico,
  }) {
    return ConfiguracaoComercio(
      comercioId: comercioId,
      nomeComercio: nomeComercio ?? this.nomeComercio,
      nomeExibicao: nomeExibicao ?? this.nomeExibicao,
      telefone: telefone ?? this.telefone,
      whatsapp: whatsapp ?? this.whatsapp,
      endereco: endereco ?? this.endereco,
      chavePix: chavePix ?? this.chavePix,
      horarioAbertura: horarioAbertura ?? this.horarioAbertura,
      horarioFechamento: horarioFechamento ?? this.horarioFechamento,
      diasFuncionamento: diasFuncionamento ?? this.diasFuncionamento,
      duracaoPadraoMinutos: duracaoPadraoMinutos ?? this.duracaoPadraoMinutos,
      notificacoesAtivas: notificacoesAtivas ?? this.notificacoesAtivas,
      confirmarExclusoes: confirmarExclusoes ?? this.confirmarExclusoes,
      permitirGaleriaClientes:
          permitirGaleriaClientes ?? this.permitirGaleriaClientes,
      documentoTipo: documentoTipo ?? this.documentoTipo,
      documento: documento ?? this.documento,
      inscricaoEstadual: inscricaoEstadual ?? this.inscricaoEstadual,
      instagram: instagram ?? this.instagram,
      cep: cep ?? this.cep,
      numero: numero ?? this.numero,
      complemento: complemento ?? this.complemento,
      bairro: bairro ?? this.bairro,
      cidade: cidade ?? this.cidade,
      estado: estado ?? this.estado,
      capaUrl: capaUrl ?? this.capaUrl,
      logoPath: logoPath ?? this.logoPath,
      corPrincipal: corPrincipal ?? this.corPrincipal,
      corSecundaria: corSecundaria ?? this.corSecundaria,
      corDestaque: corDestaque ?? this.corDestaque,
      temaModo: temaModo ?? this.temaModo,
      temaAutomatico: temaAutomatico ?? this.temaAutomatico,
    );
  }
}
