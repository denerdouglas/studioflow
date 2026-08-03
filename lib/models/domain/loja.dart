enum ModalidadeProduto { proprio, consignado }

enum TipoMovimentoLoja {
  entradaCompra,
  entradaManual,
  entradaRecebimento,
  venda,
  consumoInterno,
  perda,
  vencimento,
  devolucao,
  ajuste,
  recebimentoConsignado,
  devolucaoConsignada,
  cancelamentoVenda,
}

extension TipoMovimentoLojaDados on TipoMovimentoLoja {
  String get chave => name;
  bool get entrada => const {
    TipoMovimentoLoja.entradaCompra,
    TipoMovimentoLoja.entradaManual,
    TipoMovimentoLoja.entradaRecebimento,
    TipoMovimentoLoja.devolucao,
    TipoMovimentoLoja.recebimentoConsignado,
    TipoMovimentoLoja.cancelamentoVenda,
  }.contains(this);
}

class ProdutoLoja {
  final String id;
  final String comercioId;
  final String nome;
  final String? descricao;
  final String categoria;
  final String? marca;
  final String? codigoInterno;
  final String? codigoBarras;
  final String tipo;
  final ModalidadeProduto modalidade;
  final String? fornecedorPrincipalId;
  final double custo;
  final double precoVenda;
  final double margem;
  final double quantidadeAtual;
  final double estoqueMinimo;
  final double quantidadeSugerida;
  final String unidade;
  final double conteudoPorUnidade;
  final String unidadeConteudo;
  final bool revisaoModelagemEstoque;
  final double quantidadeEmbalagem;
  final String? lote;
  final DateTime? dataEntrada;
  final DateTime? validade;
  final String? imagem;
  final String? observacoes;
  final String origemCatalogo;
  final bool ativo;
  final DateTime criadoEm;
  final DateTime atualizadoEm;

  const ProdutoLoja({
    required this.id,
    required this.comercioId,
    required this.nome,
    this.descricao,
    required this.categoria,
    this.marca,
    this.codigoInterno,
    this.codigoBarras,
    required this.tipo,
    required this.modalidade,
    this.fornecedorPrincipalId,
    required this.custo,
    required this.precoVenda,
    required this.margem,
    required this.quantidadeAtual,
    required this.estoqueMinimo,
    required this.quantidadeSugerida,
    required this.unidade,
    this.conteudoPorUnidade = 1,
    this.unidadeConteudo = '',
    this.revisaoModelagemEstoque = false,
    required this.quantidadeEmbalagem,
    this.lote,
    this.dataEntrada,
    this.validade,
    this.imagem,
    this.observacoes,
    this.origemCatalogo = 'manual',
    required this.ativo,
    required this.criadoEm,
    required this.atualizadoEm,
  });

  bool get estoqueBaixo => ativo && quantidadeAtual <= estoqueMinimo;
  double get sugestaoReposicao => quantidadeSugerida > 0
      ? quantidadeSugerida
      : ((estoqueMinimo * 2) - quantidadeAtual).clamp(0, double.infinity);

  factory ProdutoLoja.fromMap(Map<String, Object?> map) => ProdutoLoja(
    id: map['id'] as String,
    comercioId: map['comercio_id'] as String,
    nome: map['nome'] as String,
    descricao: map['descricao'] as String?,
    categoria: map['categoria'] as String,
    marca: map['marca'] as String?,
    codigoInterno: map['codigo_interno'] as String?,
    codigoBarras: map['codigo_barras'] as String?,
    tipo: map['tipo'] as String,
    modalidade: map['modalidade'] == 'consignado'
        ? ModalidadeProduto.consignado
        : ModalidadeProduto.proprio,
    fornecedorPrincipalId: map['fornecedor_principal_id'] as String?,
    custo: (map['custo_unitario'] as num).toDouble(),
    precoVenda: (map['preco_venda'] as num? ?? 0).toDouble(),
    margem: (map['margem'] as num? ?? 0).toDouble(),
    quantidadeAtual: (map['quantidade_atual'] as num).toDouble(),
    estoqueMinimo: (map['estoque_minimo'] as num).toDouble(),
    quantidadeSugerida: (map['quantidade_sugerida'] as num? ?? 0).toDouble(),
    unidade: map['unidade'] as String,
    conteudoPorUnidade: (map['conteudo_por_unidade'] as num? ?? 1).toDouble(),
    unidadeConteudo: map['unidade_conteudo'] as String? ?? '',
    revisaoModelagemEstoque:
        (map['revisao_modelagem_estoque'] as num? ?? 0) == 1,
    quantidadeEmbalagem: (map['quantidade_embalagem'] as num? ?? 1).toDouble(),
    lote: map['lote'] as String?,
    dataEntrada: DateTime.tryParse(map['data_entrada'] as String? ?? ''),
    validade: DateTime.tryParse(map['data_validade'] as String? ?? ''),
    imagem: map['imagem'] as String?,
    observacoes: map['observacoes'] as String?,
    origemCatalogo: map['origem_catalogo'] as String? ?? 'manual',
    ativo: map['ativo'] == 1,
    criadoEm: DateTime.parse(map['data_cadastro'] as String),
    atualizadoEm:
        DateTime.tryParse(map['atualizado_em'] as String? ?? '') ??
        DateTime.parse(map['data_cadastro'] as String),
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'comercio_id': comercioId,
    'estoque_destino': 'loja',
    'nome': nome.trim(),
    'descricao': descricao?.trim(),
    'categoria': categoria.trim(),
    'marca': marca?.trim(),
    'codigo_interno': codigoInterno?.trim(),
    'codigo_barras': codigoBarras?.trim(),
    'tipo': tipo,
    'modalidade': modalidade.name,
    'fornecedor_principal_id': fornecedorPrincipalId,
    'custo_unitario': custo,
    'preco_venda': precoVenda,
    'margem': margem,
    'quantidade_atual': quantidadeAtual,
    'estoque_minimo': estoqueMinimo,
    'quantidade_sugerida': quantidadeSugerida,
    'unidade': unidade,
    'conteudo_por_unidade': conteudoPorUnidade,
    'unidade_conteudo': unidadeConteudo,
    'revisao_modelagem_estoque': revisaoModelagemEstoque ? 1 : 0,
    'quantidade_embalagem': quantidadeEmbalagem,
    'lote': lote,
    'data_entrada': dataEntrada?.toIso8601String(),
    'data_validade': validade?.toIso8601String(),
    'imagem': imagem,
    'observacoes': observacoes?.trim(),
    'origem_catalogo': origemCatalogo,
    'ativo': ativo ? 1 : 0,
    'descontar_automaticamente': 1,
    'data_cadastro': criadoEm.toIso8601String(),
    'atualizado_em': atualizadoEm.toIso8601String(),
  };
}

class FornecedorLoja {
  final String id;
  final String comercioId;
  final String nome;
  final String? nomeFantasia;
  final String? documento;
  final String? telefone;
  final String? whatsapp;
  final String? email;
  final String? endereco;
  final String? contato;
  final int prazoDias;
  final String? formasPagamento;
  final double minimoPedido;
  final bool entrega;
  final String? regioes;
  final String? observacoes;
  final String origemCatalogo;
  final bool ativo;

  const FornecedorLoja({
    required this.id,
    required this.comercioId,
    required this.nome,
    this.nomeFantasia,
    this.documento,
    this.telefone,
    this.whatsapp,
    this.email,
    this.endereco,
    this.contato,
    this.prazoDias = 0,
    this.formasPagamento,
    this.minimoPedido = 0,
    this.entrega = false,
    this.regioes,
    this.observacoes,
    this.origemCatalogo = 'manual',
    this.ativo = true,
  });

  factory FornecedorLoja.fromMap(Map<String, Object?> map) => FornecedorLoja(
    id: map['id'] as String,
    comercioId: map['comercio_id'] as String,
    nome: map['nome'] as String,
    nomeFantasia: map['nome_fantasia'] as String?,
    documento: map['documento'] as String?,
    telefone: map['telefone'] as String?,
    whatsapp: map['whatsapp'] as String?,
    email: map['email'] as String?,
    endereco: map['endereco'] as String?,
    contato: map['contato_responsavel'] as String?,
    prazoDias: map['prazo_medio_dias'] as int? ?? 0,
    formasPagamento: map['formas_pagamento'] as String?,
    minimoPedido: (map['valor_minimo_pedido'] as num? ?? 0).toDouble(),
    entrega: map['entrega_disponivel'] == 1,
    regioes: map['regioes_atendidas'] as String?,
    observacoes: map['observacoes'] as String?,
    origemCatalogo: map['origem_catalogo'] as String? ?? 'manual',
    ativo: map['ativo'] == 1,
  );
}

class ItemCarrinho {
  final ProdutoLoja produto;
  final double quantidade;
  final double desconto;
  const ItemCarrinho(this.produto, this.quantidade, {this.desconto = 0});
  double get total => (produto.precoVenda * quantidade) - desconto;
}

class OfertaReposicao {
  final String id;
  final String plataforma;
  final String titulo;
  final double quantidadeEmbalagem;
  final double preco;
  final double frete;
  final int? prazoDias;
  final double? avaliacao;
  final String? vendedor;
  final String? link;
  final bool habitual;
  const OfertaReposicao({
    required this.id,
    required this.plataforma,
    required this.titulo,
    required this.quantidadeEmbalagem,
    required this.preco,
    required this.frete,
    this.prazoDias,
    this.avaliacao,
    this.vendedor,
    this.link,
    this.habitual = false,
  });
  double get precoTotal => preco + frete;
  double get custoUnitario => precoTotal / quantidadeEmbalagem;
}

class ResumoConsignacao {
  final double recebidos;
  final double vendidos;
  final double devolvidos;
  final double disponiveis;
  final double faturamento;
  final double valorFornecedor;
  const ResumoConsignacao({
    required this.recebidos,
    required this.vendidos,
    required this.devolvidos,
    required this.disponiveis,
    required this.faturamento,
    required this.valorFornecedor,
  });
  double get valorSalao => faturamento - valorFornecedor;
}
