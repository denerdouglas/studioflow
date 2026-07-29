abstract final class IdGenerator {
  static int _ultimo = 0;

  static String temporal([DateTime? instante]) {
    final candidato = (instante ?? DateTime.now())
        .toUtc()
        .microsecondsSinceEpoch;
    if (candidato <= _ultimo) {
      _ultimo++;
    } else {
      _ultimo = candidato;
    }
    return _ultimo.toString();
  }

  const IdGenerator._();
}
