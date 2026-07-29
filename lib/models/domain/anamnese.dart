class AnamneseRegistro {
  final String id;
  final String clienteId;
  final String comercioId;
  final String tipoFicha;
  final int versao;
  final bool ativa;
  final Map<String, bool> respostas;
  final String descricaoAlergias;
  final String medicamentos;
  final String problemasPele;
  final String formatoPreferido;
  final String comprimentoPreferido;
  final String restricoes;
  final String observacoes;
  final bool clienteConfirmouInformacoes;
  final bool autorizouProcedimento;
  final String assinaturaCliente;
  final String termoVersao;
  final DateTime dataCriacao;
  final DateTime dataAtualizacao;
  final String? criadoPorId;
  final String? atualizadoPorId;
  final String? agendamentoId;

  static const camposBooleanos = <String>[
    'possui_alergias',
    'usa_medicamentos',
    'possui_problemas_pele',
    'possui_diabetes',
    'possui_pressao_alta',
    'esta_gestante',
    'fez_cirurgia_recente',
    'usa_anticoagulante',
    'possui_sensibilidade',
    'usa_acidos',
    'possui_micose',
    'possui_unha_encravada',
    'roe_unhas',
    'usa_alongamento',
    'possui_sensibilidade_ocular',
    'usa_lentes_contato',
    'fez_cirurgia_ocular',
    'possui_quimica_cabelo',
    'possui_queda_cabelo',
  ];

  const AnamneseRegistro({
    required this.id,
    required this.clienteId,
    required this.comercioId,
    required this.tipoFicha,
    required this.versao,
    required this.ativa,
    required this.respostas,
    required this.descricaoAlergias,
    required this.medicamentos,
    required this.problemasPele,
    required this.formatoPreferido,
    required this.comprimentoPreferido,
    required this.restricoes,
    required this.observacoes,
    required this.clienteConfirmouInformacoes,
    required this.autorizouProcedimento,
    required this.assinaturaCliente,
    required this.termoVersao,
    required this.dataCriacao,
    required this.dataAtualizacao,
    this.criadoPorId,
    this.atualizadoPorId,
    this.agendamentoId,
  });

  factory AnamneseRegistro.doMapa(Map<String, Object?> mapa) {
    return AnamneseRegistro(
      id: mapa['id'] as String,
      clienteId: mapa['cliente_id'] as String,
      comercioId: mapa['comercio_id'] as String? ?? '',
      tipoFicha: mapa['tipo_ficha'] as String? ?? 'geral',
      versao: mapa['versao'] as int? ?? 1,
      ativa: (mapa['ativa'] as int? ?? 1) == 1,
      respostas: {
        for (final campo in camposBooleanos)
          campo: (mapa[campo] as int? ?? 0) == 1,
      },
      descricaoAlergias: mapa['descricao_alergias'] as String? ?? '',
      medicamentos: mapa['medicamentos'] as String? ?? '',
      problemasPele: mapa['problemas_pele'] as String? ?? '',
      formatoPreferido: mapa['formato_preferido'] as String? ?? '',
      comprimentoPreferido: mapa['comprimento_preferido'] as String? ?? '',
      restricoes: mapa['restricoes'] as String? ?? '',
      observacoes: mapa['observacoes'] as String? ?? '',
      clienteConfirmouInformacoes:
          (mapa['cliente_confirmou_informacoes'] as int? ?? 0) == 1,
      autorizouProcedimento: (mapa['autorizou_procedimento'] as int? ?? 0) == 1,
      assinaturaCliente: mapa['assinatura_cliente'] as String? ?? '',
      termoVersao: mapa['termo_versao'] as String? ?? '1.0',
      dataCriacao: DateTime.parse(mapa['data_criacao'] as String),
      dataAtualizacao: DateTime.parse(mapa['data_atualizacao'] as String),
      criadoPorId: mapa['criado_por_id'] as String?,
      atualizadoPorId: mapa['atualizado_por_id'] as String?,
      agendamentoId: mapa['agendamento_id'] as String?,
    );
  }

  Map<String, Object?> paraMapa() => {
    'id': id,
    'cliente_id': clienteId,
    'comercio_id': comercioId,
    'tipo_ficha': tipoFicha,
    'versao': versao,
    'ativa': ativa ? 1 : 0,
    for (final campo in camposBooleanos)
      campo: (respostas[campo] ?? false) ? 1 : 0,
    'descricao_alergias': descricaoAlergias.trim(),
    'medicamentos': medicamentos.trim(),
    'problemas_pele': problemasPele.trim(),
    'formato_preferido': formatoPreferido.trim(),
    'comprimento_preferido': comprimentoPreferido.trim(),
    'restricoes': restricoes.trim(),
    'observacoes': observacoes.trim(),
    'cliente_confirmou_informacoes': clienteConfirmouInformacoes ? 1 : 0,
    'autorizou_procedimento': autorizouProcedimento ? 1 : 0,
    'assinatura_cliente': assinaturaCliente.trim(),
    'termo_versao': termoVersao,
    'assinatura_tipo': 'declaracao_digitada',
    'data_criacao': dataCriacao.toUtc().toIso8601String(),
    'data_atualizacao': dataAtualizacao.toUtc().toIso8601String(),
    'criado_por_id': criadoPorId,
    'atualizado_por_id': atualizadoPorId,
    'agendamento_id': agendamentoId,
  };
}
