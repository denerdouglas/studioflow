import 'package:flutter/foundation.dart';
import '../models/domain/loja.dart';
import '../repositories/agenda_repository.dart';
import '../repositories/caixa_repository.dart';
import '../repositories/loja_repository.dart';

class DashboardSummary {
  final List<AgendamentoRegistro> agendamentosHoje;
  final ResumoCaixa resumoCaixa;
  final List<ProdutoLoja> produtosBaixoEstoque;

  DashboardSummary({
    required this.agendamentosHoje,
    required this.resumoCaixa,
    required this.produtosBaixoEstoque,
  });

  bool get isEmpty =>
      agendamentosHoje.isEmpty &&
      resumoCaixa.totalEntradas == 0 &&
      resumoCaixa.totalSaidas == 0 &&
      produtosBaixoEstoque.isEmpty;

  List<AgendamentoRegistro> get agendamentosValidos =>
      agendamentosHoje.where((a) => a.status != 'cancelado').toList();

  double get receitaPrevista =>
      agendamentosValidos.fold(0.0, (s, a) => s + a.valorFinal);

  double get lucroDiario => resumoCaixa.saldo; // Saldo já é Entradas - Saídas
}

class DashboardSummaryService {
  final AgendaRepository _agendaRepository = AgendaRepository();
  final CaixaRepository _caixaRepository = CaixaRepository();
  final LojaRepository _lojaRepository = LojaRepository();

  Future<DashboardSummary> loadSummary(DateTime date) async {
    List<AgendamentoRegistro> agenda = [];
    ResumoCaixa caixa = const ResumoCaixa(
      saldo: 0,
      totalEntradas: 0,
      totalSaidas: 0,
      quantidadeEntradas: 0,
      quantidadeSaidas: 0,
    );
    List<ProdutoLoja> baixoEstoque = [];

    try {
      agenda = await _agendaRepository.listarPorDia(date);
    } catch (e, st) {
      debugPrint('DashboardSummary: Erro ao carregar agenda: $e\n$st');
    }

    try {
      caixa = await _caixaRepository.resumoDoDia(date);
    } catch (e, st) {
      debugPrint('DashboardSummary: Erro ao carregar caixa: $e\n$st');
    }

    try {
      baixoEstoque = await _lojaRepository.listarProdutos(somenteBaixo: true);
    } catch (e, st) {
      debugPrint('DashboardSummary: Erro ao carregar estoque baixo: $e\n$st');
    }

    return DashboardSummary(
      agendamentosHoje: agenda,
      resumoCaixa: caixa,
      produtosBaixoEstoque: baixoEstoque,
    );
  }
}
