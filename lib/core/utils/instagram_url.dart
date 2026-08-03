abstract final class InstagramUrl {
  static String? normalizar(String? valor) {
    var texto = (valor ?? '').trim();
    if (texto.isEmpty) return null;
    if (texto.startsWith('@')) texto = texto.substring(1);
    texto = texto.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
    texto = texto.replaceFirst(RegExp(r'^www\.', caseSensitive: false), '');
    texto = texto.replaceFirst(
      RegExp(r'^instagram\.com/', caseSensitive: false),
      '',
    );
    texto = texto.split(RegExp(r'[/?#]')).first.trim();
    if (!RegExp(r'^[A-Za-z0-9._]{1,30}$').hasMatch(texto)) return null;
    return 'https://www.instagram.com/$texto/';
  }

  static Uri? uri(String? valor) {
    final normalizado = normalizar(valor);
    return normalizado == null ? null : Uri.parse(normalizado);
  }
}
