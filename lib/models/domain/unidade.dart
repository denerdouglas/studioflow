class Unidade {
  final String id;
  final String comercioId;
  final String nome;
  final String codigo;
  final bool principal;
  final bool ativo;

  const Unidade({
    required this.id,
    required this.comercioId,
    required this.nome,
    required this.codigo,
    this.principal = false,
    this.ativo = true,
  });

  factory Unidade.doMapa(Map<String, Object?> mapa) {
    return Unidade(
      id: mapa['id'] as String,
      comercioId: mapa['comercio_id'] as String,
      nome: mapa['nome'] as String,
      codigo: mapa['codigo'] as String,
      principal: (mapa['principal'] as num? ?? 0) == 1,
      ativo: (mapa['ativo'] as num? ?? 1) == 1,
    );
  }

  Map<String, Object?> paraMapa() {
    return {
      'id': id,
      'comercio_id': comercioId,
      'nome': nome,
      'codigo': codigo,
      'principal': principal ? 1 : 0,
      'ativo': ativo ? 1 : 0,
    };
  }

  Unidade copiarCom({
    String? nome,
    String? codigo,
    bool? principal,
    bool? ativo,
  }) {
    return Unidade(
      id: id,
      comercioId: comercioId,
      nome: nome ?? this.nome,
      codigo: codigo ?? this.codigo,
      principal: principal ?? this.principal,
      ativo: ativo ?? this.ativo,
    );
  }
}
