import 'package:flutter_test/flutter_test.dart';
import 'package:studioflow/services/dashboard_summary_service.dart';
import 'package:studioflow/repositories/agenda_repository.dart';
import 'package:studioflow/repositories/caixa_repository.dart';

void main() {
  group('Sprint 3A - DashboardSummaryService Cálculos', () {
    test('Calcula corretamente o saldo, entradas e saídas', () {
      final resumoCaixaGeral = const ResumoCaixa(
        quantidadeEntradas: 2,
        totalEntradas: 150.0,
        quantidadeSaidas: 1,
        totalSaidas: 50.0,
        saldo: 100.0,
      );
      final resumoCaixaSalao = const ResumoCaixa(
        quantidadeEntradas: 2,
        totalEntradas: 150.0,
        quantidadeSaidas: 1,
        totalSaidas: 50.0,
        saldo: 100.0,
      );
      final resumoCaixaLoja = const ResumoCaixa(
        quantidadeEntradas: 2,
        totalEntradas: 150.0,
        quantidadeSaidas: 1,
        totalSaidas: 50.0,
        saldo: 100.0,
      );

      final summary = DashboardSummary(
        agendamentosHoje: [],
        resumoCaixaGeral: resumoCaixaGeral,
        resumoCaixaSalao: resumoCaixaSalao,
        resumoCaixaLoja: resumoCaixaLoja,
        produtosBaixoEstoque: [],
      );

      expect(summary.lucroDiario, 100.0);
      expect(summary.resumoCaixaGeral.totalEntradas, 150.0);
      expect(summary.resumoCaixaGeral.totalSaidas, 50.0);
    });

    test('Calcula corretamente a receita prevista ignorando cancelados', () {
      final agendamentos = [
        AgendamentoRegistro(
          id: '1',
          clienteId: 'c1',
          clienteNome: 'Maria',
          profissionalId: 'p1',
          profissionalNome: 'Profissional',
          servicoId: 's1',
          servicoNome: 'Corte',
          inicio: DateTime.now(),
          fim: DateTime.now().add(const Duration(minutes: 30)),
          status: 'agendado',
          valorServico: 50.0,
          desconto: 0.0,
          valorRecebido: 50.0,
          compareceu: false,
          confirmado: false,
          dataCriacao: DateTime.now(),
          observacoes: '',
        ),
        AgendamentoRegistro(
          id: '2',
          clienteId: 'c2',
          clienteNome: 'João',
          profissionalId: 'p1',
          profissionalNome: 'Profissional',
          servicoId: 's1',
          servicoNome: 'Corte',
          inicio: DateTime.now(),
          fim: DateTime.now().add(const Duration(minutes: 30)),
          status: 'cancelado',
          valorServico: 50.0,
          desconto: 0.0,
          valorRecebido: 50.0,
          compareceu: false,
          confirmado: false,
          dataCriacao: DateTime.now(),
          observacoes: '',
        ),
        AgendamentoRegistro(
          id: '3',
          clienteId: 'c3',
          clienteNome: 'Ana',
          profissionalId: 'p1',
          profissionalNome: 'Profissional',
          servicoId: 's1',
          servicoNome: 'Corte',
          inicio: DateTime.now(),
          fim: DateTime.now().add(const Duration(minutes: 30)),
          status: 'concluido',
          valorServico: 75.0,
          desconto: 0.0,
          valorRecebido: 75.0,
          compareceu: true,
          confirmado: true,
          dataCriacao: DateTime.now(),
          observacoes: '',
        ),
      ];

      final summary = DashboardSummary(
        agendamentosHoje: agendamentos,
        resumoCaixaGeral: ResumoCaixa.vazio(),
        resumoCaixaSalao: ResumoCaixa.vazio(),
        resumoCaixaLoja: ResumoCaixa.vazio(),
        produtosBaixoEstoque: [],
      );

      expect(summary.agendamentosValidos.length, 2);
      expect(summary.receitaPrevista, 125.0); // 50 + 75
    });

    test('Identifica estado vazio corretamente', () {
      final summary = DashboardSummary(
        agendamentosHoje: [],
        resumoCaixaGeral: ResumoCaixa.vazio(),
        resumoCaixaSalao: ResumoCaixa.vazio(),
        resumoCaixaLoja: ResumoCaixa.vazio(),
        produtosBaixoEstoque: [],
      );

      expect(summary.isEmpty, isTrue);
    });
  });
}
