enum TipoControleCatalogo {
  produtoComum,
  produtoConsignado,
  itemIndividual,
  alimentoBebida,
  produtoValidade,
  consumivel,
  outro,
}

extension TipoControleCatalogoDados on TipoControleCatalogo {
  String get chave => switch (this) {
    TipoControleCatalogo.produtoComum => 'produto_comum',
    TipoControleCatalogo.produtoConsignado => 'produto_consignado',
    TipoControleCatalogo.itemIndividual => 'item_individual',
    TipoControleCatalogo.alimentoBebida => 'alimento_bebida',
    TipoControleCatalogo.produtoValidade => 'produto_validade',
    TipoControleCatalogo.consumivel => 'consumivel',
    TipoControleCatalogo.outro => 'outro',
  };

  String get nome => switch (this) {
    TipoControleCatalogo.produtoComum => 'Produto comum',
    TipoControleCatalogo.produtoConsignado => 'Produto consignado',
    TipoControleCatalogo.itemIndividual => 'Item individual com código único',
    TipoControleCatalogo.alimentoBebida => 'Alimento/bebida',
    TipoControleCatalogo.produtoValidade => 'Produto com validade',
    TipoControleCatalogo.consumivel => 'Consumível',
    TipoControleCatalogo.outro => 'Outro',
  };

  static TipoControleCatalogo pelaChave(String? value) =>
      TipoControleCatalogo.values.firstWhere(
        (item) => item.chave == value,
        orElse: () => TipoControleCatalogo.produtoComum,
      );
}

class CatalogoLoja {
  final String id;
  final String comercioId;
  final String? unidadeId;
  final String nome;
  final String? descricao;
  final String? imagemCapa;
  final String? icone;
  final TipoControleCatalogo tipoControle;
  final bool ativo;
  final int ordem;
  final DateTime criadoEm;
  final DateTime atualizadoEm;

  const CatalogoLoja({
    required this.id,
    required this.comercioId,
    this.unidadeId,
    required this.nome,
    this.descricao,
    this.imagemCapa,
    this.icone,
    required this.tipoControle,
    required this.ativo,
    required this.ordem,
    required this.criadoEm,
    required this.atualizadoEm,
  });

  factory CatalogoLoja.fromMap(Map<String, Object?> map) => CatalogoLoja(
    id: map['id'] as String,
    comercioId: map['comercio_id'] as String,
    unidadeId: map['unidade_id'] as String?,
    nome: map['nome'] as String,
    descricao: map['descricao'] as String?,
    imagemCapa: map['imagem_capa'] as String?,
    icone: map['icone'] as String?,
    tipoControle: TipoControleCatalogoDados.pelaChave(
      map['tipo_controle'] as String?,
    ),
    ativo: map['ativo'] == 1,
    ordem: (map['ordem'] as num? ?? 0).toInt(),
    criadoEm: DateTime.parse(map['criado_em'] as String),
    atualizadoEm: DateTime.parse(map['atualizado_em'] as String),
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'comercio_id': comercioId,
    'unidade_id': unidadeId,
    'nome': nome.trim(),
    'descricao': descricao?.trim(),
    'imagem_capa': imagemCapa?.trim(),
    'icone': icone,
    'tipo_controle': tipoControle.chave,
    'ativo': ativo ? 1 : 0,
    'ordem': ordem,
    'criado_em': criadoEm.toUtc().toIso8601String(),
    'atualizado_em': atualizadoEm.toUtc().toIso8601String(),
  };

  CatalogoLoja copiarCom({
    String? nome,
    String? descricao,
    String? imagemCapa,
    String? icone,
    TipoControleCatalogo? tipoControle,
    bool? ativo,
    int? ordem,
  }) => CatalogoLoja(
    id: id,
    comercioId: comercioId,
    unidadeId: unidadeId,
    nome: nome ?? this.nome,
    descricao: descricao ?? this.descricao,
    imagemCapa: imagemCapa ?? this.imagemCapa,
    icone: icone ?? this.icone,
    tipoControle: tipoControle ?? this.tipoControle,
    ativo: ativo ?? this.ativo,
    ordem: ordem ?? this.ordem,
    criadoEm: criadoEm,
    atualizadoEm: DateTime.now().toUtc(),
  );
}
