enum ScannerConfidence {
  alta,
  media,
  baixa,
}

class ScannerField<T> {
  final T? value;
  final String source;
  final ScannerConfidence confidence;

  const ScannerField(this.value, {this.source = 'manual', this.confidence = ScannerConfidence.baixa});
}

class ScannerProductDraft {
  final ScannerField<String>? gtin;
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

  const ScannerProductDraft({
    this.gtin,
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
  });

  bool get exigeRevisaoHumana {
    // Exige revisão se qualquer campo tiver confiança baixa
    if (gtin?.confidence == ScannerConfidence.baixa) return true;
    if (nome?.confidence == ScannerConfidence.baixa) return true;
    if (marca?.confidence == ScannerConfidence.baixa) return true;
    return false;
  }
}
