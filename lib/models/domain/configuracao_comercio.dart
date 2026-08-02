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
      permitirGaleriaClientes: permitirGaleriaClientes ?? this.permitirGaleriaClientes,
    );
  }
}
