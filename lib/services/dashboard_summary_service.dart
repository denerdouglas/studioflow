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
    final resultados = await Future.wait([
      _agendaRepository.listarPorDia(date),
      _caixaRepository.resumoDoDia(date),
      _lojaRepository.listarProdutos(somenteBaixo: true),
    ]);

    return DashboardSummary(
      agendamentosHoje: resultados[0] as List<AgendamentoRegistro>,
      resumoCaixa: resultados[1] as ResumoCaixa,
      produtosBaixoEstoque: resultados[2] as List<ProdutoLoja>,
    );
  }
}
