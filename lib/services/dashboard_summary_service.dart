import 'package:flutter/foundation.dart';
import '../models/domain/loja.dart';
import '../repositories/agenda_repository.dart';
import '../repositories/caixa_repository.dart';
import '../repositories/loja_repository.dart';

class DashboardSummary {
  final List<AgendamentoRegistro> agendamentosHoje;
  final ResumoCaixa resumoCaixaGeral;
  final ResumoCaixa resumoCaixaSalao;
  final ResumoCaixa resumoCaixaLoja;
  final List<ProdutoLoja> produtosBaixoEstoque;

  DashboardSummary({
    required this.agendamentosHoje,
    required this.resumoCaixaGeral,
    required this.resumoCaixaSalao,
    required this.resumoCaixaLoja,
    required this.produtosBaixoEstoque,
  });

  bool get isEmpty =>
      agendamentosHoje.isEmpty &&
      resumoCaixaGeral.totalEntradas == 0 &&
      resumoCaixaGeral.totalSaidas == 0 &&
      produtosBaixoEstoque.isEmpty;

  List<AgendamentoRegistro> get agendamentosValidos =>
      agendamentosHoje.where((a) => a.status != 'cancelado').toList();

  double get receitaPrevista =>
      agendamentosValidos.fold(0.0, (s, a) => s + a.valorFinal);

  double get lucroDiario =>
      resumoCaixaGeral.saldo; // Saldo já é Entradas - Saídas
}

class DashboardSummaryService {
  final AgendaRepository _agendaRepository = AgendaRepository();
  final CaixaRepository _caixaRepository = CaixaRepository();
  final LojaRepository _lojaRepository = LojaRepository();

  Future<DashboardSummary> loadSummary(DateTime date) async {
    List<AgendamentoRegistro> agenda = [];
    ResumoCaixa caixaGeral = const ResumoCaixa(
      saldo: 0,
      totalEntradas: 0,
      totalSaidas: 0,
      quantidadeEntradas: 0,
      quantidadeSaidas: 0,
    );
    ResumoCaixa caixaSalao = caixaGeral;
    ResumoCaixa caixaLoja = caixaGeral;

    List<ProdutoLoja> baixoEstoque = [];

    try {
      agenda = await _agendaRepository.listarPorDia(date);
    } catch (e, st) {
      debugPrint('DashboardSummary: Erro ao carregar agenda: $e\n$st');
    }

    try {
      final resumos = await Future.wait([
        _caixaRepository.resumoDoDia(date),
        _caixaRepository.resumoDoDia(date, centroResultado: 'salao'),
        _caixaRepository.resumoDoDia(date, centroResultado: 'loja'),
      ]);
      caixaGeral = resumos[0];
      caixaSalao = resumos[1];
      caixaLoja = resumos[2];
    } catch (e, st) {
      debugPrint('DashboardSummary: Erro ao carregar caixas: $e\n$st');
    }

    try {
      baixoEstoque = await _lojaRepository.listarProdutos(somenteBaixo: true);
    } catch (e, st) {
      debugPrint('DashboardSummary: Erro ao carregar estoque baixo: $e\n$st');
    }

    return DashboardSummary(
      agendamentosHoje: agenda,
      resumoCaixaGeral: caixaGeral,
      resumoCaixaSalao: caixaSalao,
      resumoCaixaLoja: caixaLoja,
      produtosBaixoEstoque: baixoEstoque,
    );
  }
}
