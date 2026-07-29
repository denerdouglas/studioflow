class PixPayloadService {
  const PixPayloadService();

  String gerar({
    required String chave,
    required String nomeRecebedor,
    required String cidade,
    required double valor,
    required String referencia,
  }) {
    if (chave.trim().isEmpty) throw ArgumentError('Configure uma chave Pix.');
    if (valor <= 0) throw ArgumentError('O valor deve ser maior que zero.');
    final gui = _campo('00', 'br.gov.bcb.pix');
    final conta = _campo('26', '$gui${_campo('01', chave.trim())}');
    final dados = StringBuffer()
      ..write(_campo('00', '01'))
      ..write(_campo('01', '12'))
      ..write(conta)
      ..write(_campo('52', '0000'))
      ..write(_campo('53', '986'))
      ..write(_campo('54', valor.toStringAsFixed(2)))
      ..write(_campo('58', 'BR'))
      ..write(_campo('59', _texto(nomeRecebedor, 25)))
      ..write(_campo('60', _texto(cidade, 15)))
      ..write(_campo('62', _campo('05', _texto(referencia, 25))))
      ..write('6304');
    final base = dados.toString();
    return '$base${_crc16(base)}';
  }

  static String _campo(String id, String valor) =>
      '$id${valor.length.toString().padLeft(2, '0')}$valor';

  static String _texto(String valor, int limite) {
    var texto = valor
        .toUpperCase()
        .replaceAll(RegExp('[ÁÀÃÂÄ]'), 'A')
        .replaceAll(RegExp('[ÉÈÊË]'), 'E')
        .replaceAll(RegExp('[ÍÌÎÏ]'), 'I')
        .replaceAll(RegExp('[ÓÒÕÔÖ]'), 'O')
        .replaceAll(RegExp('[ÚÙÛÜ]'), 'U')
        .replaceAll('Ç', 'C')
        .replaceAll(RegExp('[^A-Z0-9 ]'), '')
        .trim();
    if (texto.isEmpty) texto = 'STUDIOFLOW';
    return texto.substring(0, texto.length.clamp(0, limite));
  }

  static String _crc16(String valor) {
    var crc = 0xFFFF;
    for (final unidade in valor.codeUnits) {
      crc ^= unidade << 8;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 0x8000) != 0
            ? ((crc << 1) ^ 0x1021) & 0xFFFF
            : (crc << 1) & 0xFFFF;
      }
    }
    return crc.toRadixString(16).toUpperCase().padLeft(4, '0');
  }
}
