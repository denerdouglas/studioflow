import 'package:uuid/uuid.dart';

/// Abstração para geração de identificadores únicos no sistema.
/// Garante que a aplicação possa ser testada com IDs determinísticos e
/// executada em produção com IDs globalmente únicos.
abstract interface class IdGenerator {
  /// Gera um novo identificador.
  String generate();

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
}

/// Implementação de produção baseada em UUID v4.
/// Garante unicidade global distribuída (offline, lote, múltiplas filiais).
class UuidIdGenerator implements IdGenerator {
  final Uuid _uuid;

  const UuidIdGenerator({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  @override
  String generate() {
    return _uuid.v4();
  }
}

/// Implementação para testes que retorna sempre o mesmo ID fornecido.
class FixedIdGenerator implements IdGenerator {
  final String fixedId;

  const FixedIdGenerator(this.fixedId);

  @override
  String generate() {
    return fixedId;
  }
}

/// Implementação para testes que retorna IDs incrementais/sequenciais.
class SequentialIdGenerator implements IdGenerator {
  final String prefix;
  int _counter;

  SequentialIdGenerator(this.prefix, {int start = 1}) : _counter = start;

  @override
  String generate() {
    final id = prefix + _counter.toString();
    _counter++;
    return id;
  }
}
