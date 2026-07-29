import 'package:sqflite/sqflite.dart';

import '../core/helpers/app_formatters.dart';
import '../database/database_service.dart';
import '../models/domain/configuracao_comercio.dart';
import '../repositories/acesso_repository.dart';
import '../repositories/configuracoes_repository.dart';

class ResumoIaLocal {
  final int clientes;
  final int agendamentosHoje;
  final List<String> horariosLivres;
  final String servicoMaisFrequente;
  final int usosServicoMaisFrequente;
  final double recebidoMes;
  final int clientesSemAtendimento;
  final int pagamentosPendentes;
  final List<String> alertas;
  final List<String> sugestoes;

  const ResumoIaLocal({
    required this.clientes,
    required this.agendamentosHoje,
    required this.horariosLivres,
    required this.servicoMaisFrequente,
    required this.usosServicoMaisFrequente,
    required this.recebidoMes,
    required this.clientesSemAtendimento,
    required this.pagamentosPendentes,
    required this.alertas,
    required this.sugestoes,
  });
}

abstract interface class IaStudioFlowProvider {
  Future<ResumoIaLocal> gerarResumo(String comercioId, {DateTime? agora});
  String responder(String pergunta, ResumoIaLocal resumo);
}

class IaLocalService implements IaStudioFlowProvider {
  final DatabaseProvider _databaseProvider;
  final ConfiguracoesRepository _configuracoes;

  IaLocalService({
    DatabaseProvider? databaseProvider,
    ConfiguracoesRepository? configuracoes,
  }) : _databaseProvider =
           databaseProvider ?? (() => DatabaseService.instance.database),
       _configuracoes = configuracoes ?? ConfiguracoesRepository();

  @override
  Future<ResumoIaLocal> gerarResumo(
    String comercioId, {
    DateTime? agora,
  }) async {
    final instante = agora ?? DateTime.now();
    final db = await _databaseProvider();
    final inicioDia = DateTime(instante.year, instante.month, instante.day);
    final fimDia = inicioDia.add(const Duration(days: 1));
    final inicioMes = DateTime(instante.year, instante.month);
    final limiteInatividade = inicioDia.subtract(const Duration(days: 60));
    final configuracao = await _configuracoes.carregar(comercioId);

    final clientes = await _inteiro(
      db,
      '''
      SELECT COUNT(*) AS total FROM clientes
      WHERE ativo = 1 AND comercio_id = ?
    ''',
      [comercioId],
    );
    final agendamentos = await _inteiro(
      db,
      '''
      SELECT COUNT(*) AS total FROM agendamentos
      WHERE comercio_id = ? AND inicio >= ? AND inicio < ? AND status != 'cancelado' AND excluido = 0
    ''',
      [comercioId, inicioDia.toIso8601String(), fimDia.toIso8601String()],
    );
    final recebimento = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(valor), 0) AS total
      FROM movimentacoes_financeiras
      WHERE comercio_id = ? AND tipo IN ('entrada', 'receita')
        AND status = 'pago' AND data >= ? AND data < ?
    ''',
      [comercioId, inicioMes.toIso8601String(), fimDia.toIso8601String()],
    );
    final inativos = await _inteiro(
      db,
      '''
      SELECT COUNT(*) AS total FROM clientes
      WHERE ativo = 1 AND comercio_id = ?
        AND (ultimo_atendimento IS NULL OR ultimo_atendimento < ?)
    ''',
      [comercioId, limiteInatividade.toIso8601String()],
    );
    final pendencias = await _inteiro(
      db,
      '''
      SELECT COUNT(*) AS total FROM movimentacoes_financeiras
      WHERE comercio_id = ? AND status = 'pendente'
    ''',
      [comercioId],
    );
    final servico = await db.rawQuery(
      '''
      SELECT s.nome, COUNT(a.id) AS total
      FROM servicos s
      LEFT JOIN agendamentos a ON a.servico_id = s.id AND a.status != 'cancelado' AND excluido = 0
      WHERE s.comercio_id = ? AND s.ativo = 1
      GROUP BY s.id, s.nome
      ORDER BY total DESC, s.nome COLLATE NOCASE
      LIMIT 1
    ''',
      [comercioId],
    );
    final ocupados = await db.query(
      'agendamentos',
      columns: ['inicio', 'fim'],
      where:
          "comercio_id = ? AND inicio >= ? AND inicio < ? AND status != 'cancelado' AND excluido = 0",
      whereArgs: [
        comercioId,
        inicioDia.toIso8601String(),
        fimDia.toIso8601String(),
      ],
    );
    final horarios = _horariosLivres(
      configuracao,
      inicioDia,
      ocupados,
      agora: instante,
    );
    final alertas = <String>[
      if (agendamentos == 0) 'A agenda de hoje está vazia.',
      if (pendencias > 0)
        '$pendencias pagamento(s) pendente(s) precisam de atenção.',
      if (horarios.isEmpty) 'Não há horários livres no restante do expediente.',
      if (inativos > 0)
        '$inativos cliente(s) estão há mais de 60 dias sem atendimento.',
    ];
    final sugestoes = <String>[
      if (agendamentos == 0)
        'Divulgue os horários de hoje para clientes que estão há mais tempo sem atendimento.',
      if (horarios.length >= 4)
        'Há vários espaços livres; considere uma ação rápida de retorno ou encaixe.',
      if (pendencias > 0) 'Revise as pendências antes do fechamento do caixa.',
      if (clientes == 0)
        'Comece cadastrando clientes para que os insights fiquem mais precisos.',
      if (agendamentos > 0 && pendencias == 0)
        'A operação está organizada. Confirme os próximos atendimentos.',
    ];
    return ResumoIaLocal(
      clientes: clientes,
      agendamentosHoje: agendamentos,
      horariosLivres: horarios,
      servicoMaisFrequente: servico.isEmpty
          ? 'Nenhum serviço cadastrado'
          : servico.first['nome'] as String,
      usosServicoMaisFrequente: servico.isEmpty
          ? 0
          : (servico.first['total'] as num).toInt(),
      recebidoMes: (recebimento.first['total'] as num).toDouble(),
      clientesSemAtendimento: inativos,
      pagamentosPendentes: pendencias,
      alertas: alertas,
      sugestoes: sugestoes,
    );
  }

  @override
  String responder(String pergunta, ResumoIaLocal resumo) {
    final texto = pergunta.toLowerCase();
    if (texto.contains('agenda')) {
      return resumo.agendamentosHoje == 0
          ? 'Sua agenda está vazia hoje. Há ${resumo.horariosLivres.length} horário(s) disponível(is).'
          : 'Você tem ${resumo.agendamentosHoje} agendamento(s) hoje e ${resumo.horariosLivres.length} horário(s) livre(s).';
    }
    if (texto.contains('clientes')) {
      return 'Existem ${resumo.clientes} cliente(s) ativo(s). ${resumo.clientesSemAtendimento} estão há mais de 60 dias sem atendimento.';
    }
    if (texto.contains('livres') || texto.contains('horários')) {
      return resumo.horariosLivres.isEmpty
          ? 'Não encontrei horários livres no restante do expediente.'
          : 'Horários livres: ${resumo.horariosLivres.join(', ')}.';
    }
    if (texto.contains('serviço')) {
      return resumo.usosServicoMaisFrequente == 0
          ? '${resumo.servicoMaisFrequente}. Ainda não há uso suficiente para criar um ranking.'
          : '${resumo.servicoMaisFrequente} aparece mais, com ${resumo.usosServicoMaisFrequente} atendimento(s).';
    }
    if (texto.contains('vendas') || texto.contains('recebimentos')) {
      return 'O total recebido neste mês é ${AppFormatters.moeda(resumo.recebidoMes)}. Existem ${resumo.pagamentosPendentes} pendência(s).';
    }
    return resumo.sugestoes.isEmpty
        ? 'Os dados estão organizados e não há sugestão crítica agora.'
        : resumo.sugestoes.first;
  }

  static Future<int> _inteiro(
    Database db,
    String sql,
    List<Object?> argumentos,
  ) async {
    final resultado = await db.rawQuery(sql, argumentos);
    return (resultado.first['total'] as num).toInt();
  }

  static List<String> _horariosLivres(
    ConfiguracaoComercio configuracao,
    DateTime dia,
    List<Map<String, Object?>> ocupados, {
    required DateTime agora,
  }) {
    if (!configuracao.diasFuncionamento.contains(dia.weekday)) return [];
    final inicio = _hora(dia, configuracao.horarioAbertura);
    final fim = _hora(dia, configuracao.horarioFechamento);
    final livres = <String>[];
    for (
      var horario = inicio;
      !horario
          .add(Duration(minutes: configuracao.duracaoPadraoMinutos))
          .isAfter(fim);
      horario = horario.add(
        Duration(minutes: configuracao.duracaoPadraoMinutos),
      )
    ) {
      final termino = horario.add(
        Duration(minutes: configuracao.duracaoPadraoMinutos),
      );
      if (dia.day == agora.day && horario.isBefore(agora)) continue;
      final conflito = ocupados.any((item) {
        final ocupadoInicio = DateTime.parse(item['inicio'] as String);
        final ocupadoFim = DateTime.parse(item['fim'] as String);
        return horario.isBefore(ocupadoFim) && termino.isAfter(ocupadoInicio);
      });
      if (!conflito) {
        livres.add(
          '${horario.hour.toString().padLeft(2, '0')}:${horario.minute.toString().padLeft(2, '0')}',
        );
      }
    }
    return livres;
  }

  static DateTime _hora(DateTime dia, String texto) {
    final partes = texto.split(':');
    return DateTime(
      dia.year,
      dia.month,
      dia.day,
      int.tryParse(partes.first) ?? 8,
      partes.length > 1 ? int.tryParse(partes[1]) ?? 0 : 0,
    );
  }
}
