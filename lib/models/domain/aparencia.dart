class ConfiguracaoAparencia {
  final String comercioId;
  final String logoPath;
  final String corPrincipal;
  final String corSecundaria;
  final String corDestaque;
  final String temaModo;
  final bool temaAutomatico;

  const ConfiguracaoAparencia({
    required this.comercioId,
    this.logoPath = '',
    this.corPrincipal = '#70569A',
    this.corSecundaria = '#8B5CF6',
    this.corDestaque = '#D9C7F2',
    this.temaModo = 'claro',
    this.temaAutomatico = true,
  });
}
