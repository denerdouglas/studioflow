enum ScannerConfidence { alta, media, baixa }

class ScannerField<T> {
  final T? value;
  final String source;
  final ScannerConfidence confidence;
  final String? reviewReason;

  const ScannerField(
    this.value, {
    this.source = 'manual',
    this.confidence = ScannerConfidence.baixa,
    this.reviewReason,
  });
}

class ScannerProductDraft {
  final ScannerField<String>? gtin;
  final ScannerField<String>? qr;
  final ScannerField<String>? referenciaComercial;
  final ScannerField<String>? referenciaInterna;
  final ScannerField<String>? nome;
  final ScannerField<String>? marca;
  final ScannerField<String>? descricao;
  final ScannerField<double>? quantidadeEmbalagem;
  final ScannerField<String>? unidade;
  final ScannerField<DateTime>? validade;
  final ScannerField<String>? lote;
  final ScannerField<String>? categoriaSugerida;
  final ScannerField<double>? preco;
  final ScannerField<String>? material;
  final ScannerField<String>? tamanhoVariacao;
  final ScannerField<double>? quantidade;
  final String? imagemFrente;
  final String? imagemVerso;
  final List<String> reviewReasons;
  final List<String> rawSignals;

  const ScannerProductDraft({
    this.gtin,
    this.qr,
    this.referenciaComercial,
    this.referenciaInterna,
    this.nome,
    this.marca,
    this.descricao,
    this.quantidadeEmbalagem,
    this.unidade,
    this.validade,
    this.lote,
    this.categoriaSugerida,
    this.preco,
    this.material,
    this.tamanhoVariacao,
    this.quantidade,
    this.imagemFrente,
    this.imagemVerso,
    this.reviewReasons = const [],
    this.rawSignals = const [],
  });

  bool get exigeRevisaoHumana {
    if (reviewReasons.isNotEmpty) return true;
    // Exige revisão se qualquer campo tiver confiança baixa
    if (gtin?.confidence == ScannerConfidence.baixa) return true;
    if (qr?.confidence == ScannerConfidence.baixa) return true;
    if (referenciaComercial?.confidence == ScannerConfidence.baixa) return true;
    if (nome?.confidence == ScannerConfidence.baixa) return true;
    if (marca?.confidence == ScannerConfidence.baixa) return true;
    if (descricao?.confidence == ScannerConfidence.baixa) return true;
    if (quantidadeEmbalagem?.confidence == ScannerConfidence.baixa) return true;
    if (unidade?.confidence == ScannerConfidence.baixa) return true;
    if (validade?.confidence == ScannerConfidence.baixa) return true;
    if (lote?.confidence == ScannerConfidence.baixa) return true;
    if (categoriaSugerida?.confidence == ScannerConfidence.baixa) return true;
    if (preco?.confidence == ScannerConfidence.baixa) return true;
    if (material?.confidence == ScannerConfidence.baixa) return true;
    if (tamanhoVariacao?.confidence == ScannerConfidence.baixa) return true;
    if (quantidade?.confidence == ScannerConfidence.baixa) return true;
    return false;
  }

  bool get precisaRevisao => exigeRevisaoHumana;

  String? get codigoComercial => referenciaComercial?.value;
}
