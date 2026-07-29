import 'package:sqflite/sqflite.dart';

import '../database/database_service.dart';
import '../models/domain/acesso.dart';
import '../services/session_controller.dart';

class RelatorioResumo {
  final double faturamento;
  final double despesas;
  final double lucro;
  final int atendimentos;
  final int clientes;
  const RelatorioResumo({
    required this.faturamento,
    required this.despesas,
    required this.lucro,
    required this.atendimentos,
    required this.clientes,
  });
}

class RelatoriosRepository {
  final DatabaseService database = DatabaseService.instance;
  Future<Database> get _db async => database.database;
  String get _comercioId {
    final usuario = SessionController.instance.usuario;
    if (usuario == null || !usuario.podeAcao(AcaoPermissao.acessarRelatorios)) {
      throw StateError('Você não possui permissão para acessar relatórios.');
    }
    return usuario.comercioId;
  }

  Future<num> _valor(String sql, [List<Object?>? args]) async {
    final db = await _db;
    final resultado = await db.rawQuery(sql, args);
    return resultado.first['total'] as num? ?? 0;
  }

  Future<RelatorioResumo> resumoGeral() async {
    final faturamento = (await _valor(
      "SELECT SUM(valor) total FROM movimentacoes_financeiras WHERE tipo='entrada' AND status='pago' AND comercio_id=?",
      [_comercioId],
    )).toDouble();
    final despesas = (await _valor(
      "SELECT SUM(valor) total FROM movimentacoes_financeiras WHERE tipo='saida' AND status='pago' AND comercio_id=?",
      [_comercioId],
    )).toDouble();
    final clientes = (await _valor(
      'SELECT COUNT(*) total FROM clientes WHERE ativo=1 AND comercio_id=?',
      [_comercioId],
    )).toInt();
    final atendimentos = (await _valor(
      "SELECT COUNT(*) total FROM agendamentos WHERE status='concluido' AND comercio_id=?",
      [_comercioId],
    )).toInt();
    return RelatorioResumo(
      faturamento: faturamento,
      despesas: despesas,
      lucro: faturamento - despesas,
      atendimentos: atendimentos,
      clientes: clientes,
    );
  }

  ({String inicio, String fim}) _periodoMes() {
    final hoje = DateTime.now();
    return (
      inicio: DateTime(hoje.year, hoje.month, 1).toIso8601String(),
      fim: DateTime(hoje.year, hoje.month + 1, 0, 23, 59, 59).toIso8601String(),
    );
  }

  Future<double> faturamentoHoje() async {
    final hoje = DateTime.now();
    final inicio = DateTime(hoje.year, hoje.month, hoje.day).toIso8601String();
    final fim = DateTime(
      hoje.year,
      hoje.month,
      hoje.day,
      23,
      59,
      59,
    ).toIso8601String();
    return (await _valor(
      "SELECT SUM(valor) total FROM movimentacoes_financeiras WHERE tipo='entrada' AND data BETWEEN ? AND ? AND comercio_id=?",
      [inicio, fim, _comercioId],
    )).toDouble();
  }

  Future<double> faturamentoMesAtual() async {
    final p = _periodoMes();
    return (await _valor(
      "SELECT SUM(valor) total FROM movimentacoes_financeiras WHERE tipo='entrada' AND data BETWEEN ? AND ? AND comercio_id=?",
      [p.inicio, p.fim, _comercioId],
    )).toDouble();
  }

  Future<double> despesasMesAtual() async {
    final p = _periodoMes();
    return (await _valor(
      "SELECT SUM(valor) total FROM movimentacoes_financeiras WHERE tipo='saida' AND data BETWEEN ? AND ? AND comercio_id=?",
      [p.inicio, p.fim, _comercioId],
    )).toDouble();
  }

  Future<int> clientesNovosMesAtual() async {
    final inicio = _periodoMes().inicio;
    return (await _valor(
      'SELECT COUNT(*) total FROM clientes WHERE data_cadastro >= ? AND comercio_id=?',
      [inicio, _comercioId],
    )).toInt();
  }

  Future<int> totalAtendimentosMesAtual() async {
    final inicio = _periodoMes().inicio;
    return (await _valor(
      "SELECT COUNT(*) total FROM agendamentos WHERE status='concluido' AND inicio >= ? AND comercio_id=?",
      [inicio, _comercioId],
    )).toInt();
  }

  Future<int> quantidadeClientes() async => (await _valor(
    'SELECT COUNT(*) total FROM clientes WHERE ativo=1 AND comercio_id=?',
    [_comercioId],
  )).toInt();
  Future<int> quantidadeServicos() async => (await _valor(
    'SELECT COUNT(*) total FROM servicos WHERE ativo=1 AND comercio_id=?',
    [_comercioId],
  )).toInt();
  Future<int> quantidadeProfissionais() async => (await _valor(
    'SELECT COUNT(*) total FROM profissionais WHERE ativo=1 AND comercio_id=?',
    [_comercioId],
  )).toInt();
  Future<double> lucroMesAtual() async =>
      await faturamentoMesAtual() - await despesasMesAtual();
}
