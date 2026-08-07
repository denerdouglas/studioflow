class AtivoImobilizado {
  final String id;
  final String businessId;
  final String estoqueId;
  final DateTime? dataAquisicao;
  final double valorAquisicao;
  final String? numeroSerie;
  final String? patrimonio;
  final String? localizacao;
  final String? condicao;
  final DateTime? garantiaAte;
  final String? observacoes;

  const AtivoImobilizado({
    required this.id,
    required this.businessId,
    required this.estoqueId,
    this.dataAquisicao,
    this.valorAquisicao = 0,
    this.numeroSerie,
    this.patrimonio,
    this.localizacao,
    this.condicao,
    this.garantiaAte,
    this.observacoes,
  });

  factory AtivoImobilizado.fromMap(Map<String, Object?> map) =>
      AtivoImobilizado(
        id: map['id'] as String,
        businessId: map['business_id'] as String,
        estoqueId: map['estoque_id'] as String,
        dataAquisicao: map['data_aquisicao'] != null
            ? DateTime.tryParse(map['data_aquisicao'] as String)
            : null,
        valorAquisicao: (map['valor_aquisicao'] as num? ?? 0).toDouble(),
        numeroSerie: map['numero_serie'] as String?,
        patrimonio: map['patrimonio'] as String?,
        localizacao: map['localizacao'] as String?,
        condicao: map['condicao'] as String?,
        garantiaAte: map['garantia_ate'] != null
            ? DateTime.tryParse(map['garantia_ate'] as String)
            : null,
        observacoes: map['observacoes'] as String?,
      );

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'business_id': businessId,
      'estoque_id': estoqueId,
      'data_aquisicao': dataAquisicao?.toUtc().toIso8601String(),
      'valor_aquisicao': valorAquisicao,
      'numero_serie': numeroSerie,
      'patrimonio': patrimonio,
      'localizacao': localizacao,
      'condicao': condicao,
      'garantia_ate': garantiaAte?.toUtc().toIso8601String(),
      'observacoes': observacoes,
    };
  }

  AtivoImobilizado copiarCom({
    String? localizacao,
    String? condicao,
    String? observacoes,
  }) {
    return AtivoImobilizado(
      id: id,
      businessId: businessId,
      estoqueId: estoqueId,
      dataAquisicao: dataAquisicao,
      valorAquisicao: valorAquisicao,
      numeroSerie: numeroSerie,
      patrimonio: patrimonio,
      localizacao: localizacao ?? this.localizacao,
      condicao: condicao ?? this.condicao,
      garantiaAte: garantiaAte,
      observacoes: observacoes ?? this.observacoes,
    );
  }
}
