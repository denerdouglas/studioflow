abstract final class AppFormatters {
  static String moeda(double valor) {
    return 'R\$ ${valor.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  static String data(DateTime valor) {
    final dia = valor.day.toString().padLeft(2, '0');
    final mes = valor.month.toString().padLeft(2, '0');
    return '$dia/$mes/${valor.year}';
  }

  static String hora(DateTime valor) {
    final hora = valor.hour.toString().padLeft(2, '0');
    final minuto = valor.minute.toString().padLeft(2, '0');
    return '$hora:$minuto';
  }

  const AppFormatters._();
}
