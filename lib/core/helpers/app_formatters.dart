abstract final class AppFormatters {
  static String moeda(double valor) {
    final negative = valor < 0;
    final parts = valor.abs().toStringAsFixed(2).split('.');
    final digits = parts.first;
    final groups = <String>[];
    for (var end = digits.length; end > 0; end -= 3) {
      groups.insert(0, digits.substring((end - 3).clamp(0, end), end));
    }
    return 'R\$ ${negative ? '-' : ''}${groups.join('.')},${parts.last}';
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
