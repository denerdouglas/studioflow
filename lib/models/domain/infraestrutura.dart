class UnidadeNegocio {
  final String id;
  final String comercioId;
  final String nome;
  final String codigo;
  final bool principal;
  final bool ativo;

  const UnidadeNegocio({
    required this.id,
    required this.comercioId,
    required this.nome,
    required this.codigo,
    required this.principal,
    required this.ativo,
  });

  factory UnidadeNegocio.fromMap(Map<String, Object?> map) => UnidadeNegocio(
    id: map['id'] as String,
    comercioId: map['comercio_id'] as String,
    nome: map['nome'] as String,
    codigo: map['codigo'] as String,
    principal: map['principal'] == 1,
    ativo: map['ativo'] == 1,
  );
}

class EstadoInfraestrutura {
  final UnidadeNegocio unidadePrincipal;
  final String provedorBackend;
  final String? endpointPublico;
  final bool sincronizacaoAtiva;
  final int operacoesPendentes;
  final int operacoesEmErro;
  final int operacoesSincronizadas;
  final int ultimoCursor;
  final DateTime? ultimaSincronizacao;
  final String? ultimoErro;

  const EstadoInfraestrutura({
    required this.unidadePrincipal,
    required this.provedorBackend,
    required this.endpointPublico,
    required this.sincronizacaoAtiva,
    required this.operacoesPendentes,
    this.operacoesEmErro = 0,
    this.operacoesSincronizadas = 0,
    this.ultimoCursor = 0,
    this.ultimaSincronizacao,
    this.ultimoErro,
  });

  bool get backendConfigurado =>
      provedorBackend != 'nenhum' && (endpointPublico?.isNotEmpty ?? false);
}

class OperacaoSincronizacao {
  final String id;
  final String comercioId;
  final String? unidadeId;
  final String entidade;
  final String entidadeId;
  final String operacao;
  final String payloadJson;
  final int versaoLocal;
  final String status;
  final int tentativas;
  final String? ultimoErro;
  final DateTime criadaEm;

  const OperacaoSincronizacao({
    required this.id,
    required this.comercioId,
    required this.unidadeId,
    required this.entidade,
    required this.entidadeId,
    required this.operacao,
    required this.payloadJson,
    required this.versaoLocal,
    required this.status,
    required this.tentativas,
    required this.ultimoErro,
    required this.criadaEm,
  });
}
