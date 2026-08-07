import 'package:flutter_test/flutter_test.dart';
import 'package:studioflow/domain/services/agenda_conflict_checker.dart';
import 'package:studioflow/repositories/agenda_repository.dart';

void main() {
  group('AgendaConflictChecker', () {
    test('Nenhum conflito entre novos vazios', () {
      expect(
        () => AgendaConflictChecker.validar(novos: <AgendamentoRegistro>[], existentes: <AgendamentoRegistro>[]),
        returnsNormally,
      );
    });

    AgendamentoRegistro criarDummy({
      required String id,
      required String profissionalId,
      required DateTime inicio,
      required DateTime fim,
    }) {
      return AgendamentoRegistro(
        id: id,
        clienteId: 'c1',
        clienteNome: 'Cliente 1',
        profissionalId: profissionalId,
        profissionalNome: 'Profissional 1',
        servicoId: 's1',
        servicoNome: 'Servico 1',
        inicio: inicio,
        fim: fim,
        status: 'agendado',
        valorServico: 0,
        desconto: 0,
        valorRecebido: 0,
        confirmado: false,
        compareceu: false,
        encaixe: false,
        dataCriacao: DateTime.now(),
      );
    }

    test('Deve detectar sobreposição com agendamento existente', () {
      final existentes = [
        criarDummy(id: '1', profissionalId: 'p1', inicio: DateTime(2025, 1, 1, 10, 0), fim: DateTime(2025, 1, 1, 11, 0)),
      ];

      final novos = [
        criarDummy(id: 'novo', profissionalId: 'p1', inicio: DateTime(2025, 1, 1, 10, 30), fim: DateTime(2025, 1, 1, 11, 30)),
      ];

      expect(
        () => AgendaConflictChecker.validar(novos: novos, existentes: existentes),
        throwsA(isA<ConflitoAgendaException>()),
      );
    });

    test('Não deve detectar sobreposição se horários forem consecutivos', () {
      final existentes = [
        criarDummy(id: '1', profissionalId: 'p1', inicio: DateTime(2025, 1, 1, 10, 0), fim: DateTime(2025, 1, 1, 11, 0)),
      ];

      final novos = [
        criarDummy(id: 'novo', profissionalId: 'p1', inicio: DateTime(2025, 1, 1, 11, 0), fim: DateTime(2025, 1, 1, 12, 0)),
      ];

      expect(
        () => AgendaConflictChecker.validar(novos: novos, existentes: existentes),
        returnsNormally,
      );
    });

    test('Deve detectar sobreposição dentro dos próprios novos agendamentos', () {
      final novos = [
        criarDummy(id: 'novo1', profissionalId: 'p1', inicio: DateTime(2025, 1, 1, 10, 0), fim: DateTime(2025, 1, 1, 11, 0)),
        criarDummy(id: 'novo2', profissionalId: 'p1', inicio: DateTime(2025, 1, 1, 10, 30), fim: DateTime(2025, 1, 1, 11, 30)),
      ];

      expect(
        () => AgendaConflictChecker.validar(novos: novos, existentes: <AgendamentoRegistro>[]),
        throwsA(isA<ConflitoAgendaException>()),
      );
    });
    
    test('Ignorar si mesmo na edição', () {
      final existentes = [
        criarDummy(id: '1', profissionalId: 'p1', inicio: DateTime(2025, 1, 1, 10, 0), fim: DateTime(2025, 1, 1, 11, 0)),
      ];

      final novos = [
        criarDummy(id: '1', profissionalId: 'p1', inicio: DateTime(2025, 1, 1, 10, 30), fim: DateTime(2025, 1, 1, 11, 30)),
      ];

      expect(
        () => AgendaConflictChecker.validar(novos: novos, existentes: existentes),
        returnsNormally,
      );
    });
  });
}
