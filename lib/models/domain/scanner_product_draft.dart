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
  final ScannerField<String>? referenciaComercial;
  final ScannerField<String>? nome;
  final ScannerField<String>? marca;
  final ScannerField<String>? descricao;
  final ScannerField<double>? quantidadeEmbalagem;
  final ScannerField<String>? unidade;
  final ScannerField<DateTime>? validade;
  final ScannerField<String>? lote;
  final ScannerField<String>? categoriaSugerida;
  final String? imagemFrente;
  final String? imagemVerso;
  final List<String> reviewReasons;

  const ScannerProductDraft({
    this.gtin,
    this.referenciaComercial,
    this.nome,
    this.marca,
    this.descricao,
    this.quantidadeEmbalagem,
    this.unidade,
    this.validade,
    this.lote,
    this.categoriaSugerida,
    this.imagemFrente,
    this.imagemVerso,
    this.reviewReasons = const [],
  });

  bool get exigeRevisaoHumana {
    if (reviewReasons.isNotEmpty) return true;
    // Exige revisão se qualquer campo tiver confiança baixa
    if (gtin?.confidence == ScannerConfidence.baixa) return true;
    if (referenciaComercial?.confidence == ScannerConfidence.baixa) return true;
    if (nome?.confidence == ScannerConfidence.baixa) return true;
    if (marca?.confidence == ScannerConfidence.baixa) return true;
    if (descricao?.confidence == ScannerConfidence.baixa) return true;
    if (quantidadeEmbalagem?.confidence == ScannerConfidence.baixa) return true;
    if (unidade?.confidence == ScannerConfidence.baixa) return true;
    if (validade?.confidence == ScannerConfidence.baixa) return true;
    if (lote?.confidence == ScannerConfidence.baixa) return true;
    if (categoriaSugerida?.confidence == ScannerConfidence.baixa) return true;
    return false;
  }
}
