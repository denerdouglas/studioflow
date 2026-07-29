class ConfiguracaoComercial {
  final String comercioId;
  final String cep;
  final String rua;
  final String numero;
  final String complemento;
  final String bairro;
  final String cidade;
  final String estado;
  final String pontoReferencia;
  final String linkLocalizacao;
  final String latitude;
  final String longitude;

  const ConfiguracaoComercial({
    required this.comercioId,
    this.cep = '',
    this.rua = '',
    this.numero = '',
    this.complemento = '',
    this.bairro = '',
    this.cidade = '',
    this.estado = '',
    this.pontoReferencia = '',
    this.linkLocalizacao = '',
    this.latitude = '',
    this.longitude = '',
  });

  String get enderecoCompleto => <String>[
    [rua, numero].where((item) => item.trim().isNotEmpty).join(', '),
    complemento,
    bairro,
    [cidade, estado].where((item) => item.trim().isNotEmpty).join(' - '),
    if (cep.trim().isNotEmpty) 'CEP $cep',
  ].where((item) => item.trim().isNotEmpty).join(', ');

  String get destinoRota {
    if (latitude.trim().isNotEmpty && longitude.trim().isNotEmpty) {
      return '${latitude.trim()},${longitude.trim()}';
    }
    return enderecoCompleto;
  }

  Uri get uriRota => linkLocalizacao.trim().isNotEmpty
      ? Uri.parse(linkLocalizacao.trim())
      : Uri.https('www.google.com', '/maps/search/', {
          'api': '1',
          'query': destinoRota,
        });
}
