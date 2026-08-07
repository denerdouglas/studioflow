import '../../repositories/agenda_repository.dart';

class AgendaConflictChecker {
  static const _estadosBloqueantes = ['agendado', 'confirmado', 'emAtendimento'];

  /// Verifica se há conflito entre uma lista de [novos] agendamentos
  /// e a lista de [existentes] no banco.
  /// Lança [ConflitoAgendaException] se houver sobreposição indevida.
  static void validar({
    required List<AgendamentoRegistro> novos,
    required List<AgendamentoRegistro> existentes,
    Set<String>? ignoredAppointmentIds,
  }) {
    final existentesRelevantes = existentes
        .where((e) => _estadosBloqueantes.contains(e.status))
        .toList();

    for (var novo in novos) {
      // 1. Verificar conflito com os agendamentos já existentes no banco
      for (var existente in existentesRelevantes) {
        // Sempre ignorar a si mesmo (em caso de edição)
        if (novo.id == existente.id) continue;
        // Ignorar de acordo com o Set explícito de ignorados (ex: remarcação de grupo)
        if (ignoredAppointmentIds != null && ignoredAppointmentIds.contains(existente.id)) continue;

        if (_isSobreposto(novo, existente)) {
          if (_temRecursoEmComum(novo, existente)) {
            throw ConflitoAgendaException(
              'Conflito detectado com um agendamento existente.',
              [],
            );
          }
        }
      }

      // 2. Verificar conflito DENTRO DO PRÓPRIO GRUPO (entre os novos)
      // Se eu agendar João para 10:00-10:30 e João novamente 10:15-10:45, é conflito.
      for (var outroNovo in novos) {
        if (novo.id == outroNovo.id) continue;

        if (_isSobreposto(novo, outroNovo)) {
          if (_temRecursoEmComum(novo, outroNovo)) {
            throw ConflitoAgendaException(
              'Conflito detectado dentro do próprio grupo de serviços.',
              [],
            );
          }
        }
      }
    }
  }

  static bool _isSobreposto(AgendamentoRegistro a, AgendamentoRegistro b) {
    // inicio < outroFim AND fim > outroInicio
    return a.inicio.isBefore(b.fim) && a.fim.isAfter(b.inicio);
  }

  static bool _temRecursoEmComum(AgendamentoRegistro a, AgendamentoRegistro b) {
    // Nesta etapa só validamos profissional_id pois os outros recursos (sala, cadeira)
    // ainda não estão mapeados no AgendamentoRegistro do Repositório de forma estrita.
    // Mas a lógica está preparada.
    if (a.profissionalId == b.profissionalId) return true;
    
    // Futuro: se a.salaId != null && a.salaId == b.salaId return true;
    return false;
  }
}
