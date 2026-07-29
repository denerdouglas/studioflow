class CredenciaisBackend {
  final String endpoint;
  final String login;
  final String senha;

  const CredenciaisBackend({
    required this.endpoint,
    required this.login,
    required this.senha,
  });
}

class SessaoBackend {
  final String comercioId;
  final String usuarioId;
  final String accessToken;
  final String refreshToken;
  final DateTime refreshExpiraEm;

  const SessaoBackend({
    required this.comercioId,
    required this.usuarioId,
    required this.accessToken,
    required this.refreshToken,
    required this.refreshExpiraEm,
  });
}

class ResultadoSincronizacao {
  final int enviadas;
  final int recebidas;
  final int conflitos;
  final int pendentes;

  const ResultadoSincronizacao({
    required this.enviadas,
    required this.recebidas,
    required this.conflitos,
    required this.pendentes,
  });
}
