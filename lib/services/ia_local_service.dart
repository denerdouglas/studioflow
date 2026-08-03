import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/utils/id_generator.dart';

import '../core/helpers/app_formatters.dart';
import '../database/database_service.dart';
import '../models/domain/acesso.dart';
import '../models/domain/configuracao_comercio.dart';
import '../repositories/acesso_repository.dart';
import '../repositories/configuracoes_repository.dart';
import 'session_controller.dart';

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
  Future<String> conversar(
    String pergunta,
    String comercioId, {
    String? unidadeId,
  });
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

  @override
  Future<String> conversar(
    String pergunta,
    String comercioId, {
    String? unidadeId,
  }) async {
    final db = await _databaseProvider();
    final texto = pergunta.trim().toLowerCase();
    if (texto.isEmpty) throw StateError('Digite uma pergunta.');
    final usuario = SessionController.instance.usuario;
    if (usuario == null || usuario.comercioId != comercioId) {
      throw StateError('Sessão inválida.');
    }
    final now = DateTime.now().toUtc();
    final conversationId = '${comercioId}_${usuario.id}';
    await db.insert('ia_conversas', {
      'id': conversationId,
      'comercio_id': comercioId,
      'usuario_id': usuario.id,
      'unidade_id': unidadeId,
      'contexto': jsonEncode({'fonte': 'dados_locais'}),
      'criado_em': now.toIso8601String(),
      'atualizado_em': now.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.update(
      'ia_conversas',
      {'unidade_id': unidadeId, 'atualizado_em': now.toIso8601String()},
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [conversationId, comercioId],
    );
    await _saveMessage(
      db,
      conversationId,
      comercioId,
      usuario.id,
      'usuario',
      pergunta,
      null,
    );

    String answer;
    String intent = 'resumo';
    if (texto.contains('amanhã') || texto.contains('amanha')) {
      intent = 'agenda_amanha';
      if (!usuario.pode(ModuloPermissao.agenda)) {
        throw StateError('Acesso à agenda não autorizado.');
      }
      final tomorrow = DateTime(
        now.year,
        now.month,
        now.day,
      ).add(const Duration(days: 1));
      final end = tomorrow.add(const Duration(days: 1));
      final rows = await db.rawQuery(
        '''SELECT a.inicio, c.nome cliente_nome, s.nome servico_nome
        FROM agendamentos a JOIN clientes c ON c.id=a.cliente_id JOIN servicos s ON s.id=a.servico_id
        WHERE a.comercio_id=? AND a.inicio>=? AND a.inicio<? AND a.status!='cancelado' AND a.excluido=0
        ${unidadeId == null ? '' : 'AND (a.unidade_id=? OR a.unidade_id IS NULL)'} ORDER BY a.inicio''',
        [
          comercioId,
          tomorrow.toIso8601String(),
          end.toIso8601String(),
          ?unidadeId,
        ],
      );
      answer = rows.isEmpty
          ? 'A agenda de amanhã está vazia.'
          : rows
                .map(
                  (row) =>
                      '${DateTime.parse(row['inicio'] as String).toLocal().hour.toString().padLeft(2, '0')}:${DateTime.parse(row['inicio'] as String).toLocal().minute.toString().padLeft(2, '0')} — ${row['cliente_nome']} — ${row['servico_nome']}',
                )
                .join('\n');
    } else if (texto.contains('próxim') || texto.contains('proxim')) {
      intent = 'proximos_atendimentos';
      final rows = await db.rawQuery(
        '''SELECT a.inicio,c.nome cliente_nome,s.nome servico_nome
        FROM agendamentos a JOIN clientes c ON c.id=a.cliente_id JOIN servicos s ON s.id=a.servico_id
        WHERE a.comercio_id=? AND a.inicio>=? AND a.status!='cancelado' AND a.excluido=0
        ORDER BY a.inicio LIMIT 5''',
        [comercioId, now.toIso8601String()],
      );
      answer = rows.isEmpty
          ? 'Não há próximos atendimentos.'
          : rows
                .map(
                  (row) =>
                      '${DateTime.parse(row['inicio'] as String).toLocal()} — ${row['cliente_nome']} — ${row['servico_nome']}',
                )
                .join('\n');
    } else if (texto.contains('localizar cliente') ||
        texto.contains('buscar cliente')) {
      intent = 'localizar_cliente';
      if (!usuario.pode(ModuloPermissao.clientes)) {
        throw StateError('Acesso a clientes não autorizado.');
      }
      final term = texto
          .replaceAll('localizar cliente', '')
          .replaceAll('buscar cliente', '')
          .trim();
      final rows = await db.query(
        'clientes',
        columns: ['id', 'nome', 'whatsapp'],
        where: 'comercio_id=? AND ativo=1 AND (nome LIKE ? OR whatsapp LIKE ?)',
        whereArgs: [comercioId, '%$term%', '%$term%'],
        limit: 10,
      );
      answer = rows.isEmpty
          ? 'Cliente não encontrado.'
          : rows.map((row) => '${row['nome']} — ${row['whatsapp']}').join('\n');
    } else if (texto.contains('saldo') && texto.contains('cliente')) {
      intent = 'saldo_cliente';
      final result = await db.rawQuery(
        '''SELECT c.nome,COALESCE(SUM(r.valor_total-r.valor_recebido),0) saldo
        FROM clientes c LEFT JOIN contas_receber_loja r ON r.cliente_id=c.id AND r.status!='paga'
        WHERE c.comercio_id=? AND c.ativo=1 GROUP BY c.id,c.nome HAVING saldo>0 ORDER BY saldo DESC''',
        [comercioId],
      );
      answer = result.isEmpty
          ? 'Nenhum cliente possui saldo pendente.'
          : result
                .map(
                  (row) =>
                      '${row['nome']}: ${AppFormatters.moeda((row['saldo'] as num).toDouble())}',
                )
                .join('\n');
    } else if (texto.contains('comissão') || texto.contains('comissao')) {
      intent = 'comissoes';
      if (!usuario.pode(ModuloPermissao.financeiro)) {
        throw StateError('Acesso financeiro não autorizado.');
      }
      final result = await db.rawQuery(
        "SELECT COALESCE(SUM(valor),0) total FROM comanda_comissoes WHERE comercio_id=? AND status='pendente'",
        [comercioId],
      );
      answer =
          'Comissões pendentes: ${AppFormatters.moeda((result.single['total'] as num).toDouble())}.';
    } else if (texto.contains('faturamento')) {
      intent = 'faturamento';
      if (!usuario.pode(ModuloPermissao.financeiro)) {
        throw StateError('Acesso financeiro não autorizado.');
      }
      final month = DateTime.utc(now.year, now.month);
      final result = await db.rawQuery(
        "SELECT COALESCE(SUM(valor),0) total FROM movimentacoes_financeiras WHERE comercio_id=? AND tipo IN ('entrada','receita') AND status='pago' AND data>=?",
        [comercioId, month.toIso8601String()],
      );
      answer =
          'Faturamento recebido no mês: ${AppFormatters.moeda((result.single['total'] as num).toDouble())}.';
    } else if (texto.contains('estoque') ||
        texto.contains('acabando') ||
        texto.contains('repor')) {
      intent = 'estoque_baixo';
      if (!usuario.pode(ModuloPermissao.estoque)) {
        throw StateError('Acesso ao estoque não autorizado.');
      }
      final rows = await db.rawQuery(
        '''SELECT nome, quantidade_atual, estoque_minimo, unidade
           FROM estoque WHERE comercio_id = ? AND ativo = 1
           AND quantidade_atual <= estoque_minimo
           ${unidadeId == null ? '' : 'AND (unidade_id = ? OR unidade_id IS NULL)'}
           ORDER BY (estoque_minimo-quantidade_atual) DESC, nome''',
        [comercioId, ?unidadeId],
      );
      answer = rows.isEmpty
          ? 'Nenhum produto está abaixo do estoque mínimo na unidade ativa.'
          : rows
                .map((row) {
                  final current = (row['quantidade_atual'] as num).toDouble();
                  final minimum = (row['estoque_minimo'] as num).toDouble();
                  return '${row['nome']}: atual $current ${row['unidade']}, mínimo $minimum, reposição sugerida ${(minimum - current).clamp(0, double.infinity)}.';
                })
                .join('\n');
    } else if (texto.contains('comanda') || texto.contains('venda')) {
      intent = 'comandas';
      if (!usuario.pode(ModuloPermissao.lojaSalao)) {
        throw StateError('Acesso à loja não autorizado.');
      }
      final result = await db.rawQuery(
        "SELECT COUNT(*) total, COALESCE(SUM(total),0) valor FROM comandas_loja WHERE comercio_id=? AND status!='cancelada'",
        [comercioId],
      );
      answer =
          'Há ${result.single['total']} comanda(s), totalizando ${AppFormatters.moeda((result.single['valor'] as num).toDouble())}.';
    } else if (texto.contains('receber') ||
        texto.contains('pendente') ||
        texto.contains('financeiro')) {
      intent = 'contas_receber';
      if (!usuario.pode(ModuloPermissao.financeiro)) {
        throw StateError('Acesso financeiro não autorizado.');
      }
      final result = await db.rawQuery(
        "SELECT COUNT(*) total, COALESCE(SUM(valor_total-valor_recebido),0) saldo FROM contas_receber_loja WHERE comercio_id=? AND status!='paga'",
        [comercioId],
      );
      answer =
          'Existem ${result.single['total']} conta(s) a receber, com saldo de ${AppFormatters.moeda((result.single['saldo'] as num).toDouble())}.';
    } else if (texto.contains('joia') || texto.contains('consigna')) {
      intent = 'consignacoes';
      if (!usuario.podeAcao(AcaoPermissao.acessarConsignacao)) {
        throw StateError('Acesso à consignação não autorizado.');
      }
      final result = await db.rawQuery(
        "SELECT COUNT(*) total FROM pecas_unicas WHERE comercio_id=? AND status='disponivel'",
        [comercioId],
      );
      answer =
          'Há ${result.single['total']} peça(s) única(s) consignada(s) disponível(is).';
    } else {
      final summary = await gerarResumo(comercioId, agora: now.toLocal());
      answer = responder(pergunta, summary);
    }
    await _saveMessage(
      db,
      conversationId,
      comercioId,
      usuario.id,
      'assistente',
      answer,
      intent,
    );
    await db.insert('ia_auditoria', {
      'id': IdGenerator.temporal(),
      'comercio_id': comercioId,
      'usuario_id': usuario.id,
      'unidade_id': unidadeId,
      'intencao': intent,
      'acao': 'consulta',
      'confirmado': 1,
      'resultado': 'sucesso',
      'criado_em': now.toIso8601String(),
    });
    return answer;
  }

  static Future<void> _saveMessage(
    Database db,
    String conversationId,
    String commerceId,
    String userId,
    String role,
    String content,
    String? intent,
  ) => db.insert('ia_mensagens', {
    'id': IdGenerator.temporal(),
    'conversa_id': conversationId,
    'comercio_id': commerceId,
    'usuario_id': userId,
    'papel': role,
    'conteudo': content,
    'intencao': intent,
    'criado_em': DateTime.now().toUtc().toIso8601String(),
  });
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
