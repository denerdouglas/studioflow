abstract final class PhoneNormalizer {
  static String? paraWhatsapp(String? valor) {
    var numero = (valor ?? '').replaceAll(RegExp(r'\D'), '');
    if (numero.startsWith('00')) numero = numero.substring(2);
    if (numero.startsWith('55') && numero.length > 13) {
      while (numero.startsWith('5555')) {
        numero = numero.substring(2);
      }
    }
    if (!numero.startsWith('55')) numero = '55$numero';
    if (numero.length != 12 && numero.length != 13) return null;
    final ddd = int.tryParse(numero.substring(2, 4));
    if (ddd == null || ddd < 11 || ddd > 99) return null;
    final local = numero.substring(4);
    if (local.length != 8 && local.length != 9) return null;
    if (RegExp(r'^(\d)\1+$').hasMatch(local)) return null;
    return numero;
  }

  static String somenteDigitos(String? valor) =>
      (valor ?? '').replaceAll(RegExp(r'\D'), '');
}
