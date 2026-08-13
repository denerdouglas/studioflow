class ConsignmentImportItem {
  final String codigo;
  final String categoria;
  final String material;
  final int quantidade;
  final double valorUnitario;
  final String descricao;
  final String observacao;

  const ConsignmentImportItem({
    required this.codigo,
    required this.categoria,
    required this.material,
    required this.quantidade,
    required this.valorUnitario,
    this.descricao = '',
    this.observacao = '',
  });

  Map<String, Object?> toPieceMap() => {
    'codigo': codigo,
    'categoria': categoria,
    'nome': descricao.isEmpty ? categoria : descricao,
    'descricao': descricao.isEmpty ? categoria : descricao,
    'quantidade': quantidade,
    'preco': valorUnitario,
    'material': material,
    'observacoes': observacao,
  };
}

class ConsignmentPendingLine {
  final int lineNumber;
  final String originalText;
  final String reason;

  const ConsignmentPendingLine({
    required this.lineNumber,
    required this.originalText,
    required this.reason,
  });
}

class ConsignmentDocumentImport {
  final String? representante;
  final String? contrato;
  final String? mostruario;
  final DateTime? dataEnvio;
  final DateTime? dataTroca;
  final DateTime? dataPagamento;
  final String? zonaVenda;
  final List<ConsignmentImportItem> itens;
  final List<ConsignmentPendingLine> linhasPendentes;
  final bool usedOcr;
  final int? quantidadeDeclarada;
  final double? totalDeclarado;

  const ConsignmentDocumentImport({
    this.representante,
    this.contrato,
    this.mostruario,
    this.dataEnvio,
    this.dataTroca,
    this.dataPagamento,
    this.zonaVenda,
    required this.itens,
    this.linhasPendentes = const [],
    this.usedOcr = false,
    this.quantidadeDeclarada,
    this.totalDeclarado,
  });

  int get quantidadeImportada =>
      itens.fold(0, (total, item) => total + item.quantidade);

  double get totalImportado => itens.fold(
    0,
    (total, item) => total + item.quantidade * item.valorUnitario,
  );

  bool get divergeDoDeclarado =>
      (quantidadeDeclarada != null &&
          quantidadeDeclarada != quantidadeImportada) ||
      (totalDeclarado != null &&
          (totalDeclarado! - totalImportado).abs() > 0.01);

  ConsignmentDocumentImport copyWith({bool? usedOcr}) =>
      ConsignmentDocumentImport(
        representante: representante,
        contrato: contrato,
        mostruario: mostruario,
        dataEnvio: dataEnvio,
        dataTroca: dataTroca,
        dataPagamento: dataPagamento,
        zonaVenda: zonaVenda,
        itens: itens,
        linhasPendentes: linhasPendentes,
        usedOcr: usedOcr ?? this.usedOcr,
        quantidadeDeclarada: quantidadeDeclarada,
        totalDeclarado: totalDeclarado,
      );
}
