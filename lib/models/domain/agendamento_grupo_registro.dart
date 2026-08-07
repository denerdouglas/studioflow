class AgendamentoGrupoRegistro {
  final String id;
  final String businessId;
  final String clienteId;
  final String? comandaId;
  final String? status;
  final String? observacoes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AgendamentoGrupoRegistro({
    required this.id,
    required this.businessId,
    required this.clienteId,
    this.comandaId,
    this.status,
    this.observacoes,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'business_id': businessId,
      'cliente_id': clienteId,
      'comanda_id': comandaId,
      'status': status,
      'observacoes': observacoes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory AgendamentoGrupoRegistro.fromMap(Map<String, dynamic> map) {
    return AgendamentoGrupoRegistro(
      id: map['id'] as String,
      businessId: map['business_id'] as String,
      clienteId: map['cliente_id'] as String,
      comandaId: map['comanda_id'] as String?,
      status: map['status'] as String?,
      observacoes: map['observacoes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
