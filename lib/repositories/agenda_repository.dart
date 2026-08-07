import 'dart:convert';
import 'package:sqflite/sqflite.dart';

import '../database/database_service.dart';
import '../models/domain/acesso.dart';
import '../services/session_controller.dart';
import '../services/whatsapp_queue_service.dart';
import '../models/domain/agendamento_grupo_registro.dart';
import '../domain/services/agenda_conflict_checker.dart';
import 'agenda_completa_repository.dart';
import 'pacotes_repository.dart';

class ConflitoAgendaException implements Exception {
  final String mensagem;
  final List<DateTime> sugestoes;
  const ConflitoAgendaException(this.mensagem, this.sugestoes);

  @override
  String toString() => mensagem;
}

class AgendamentoRegistro {
  final String id;

  final String clienteId;
  final String clienteNome;

  final String profissionalId;
  final String profissionalNome;

  final String servicoId;
  final String servicoNome;

  final DateTime inicio;
  final DateTime fim;

  final String status;

  final double valorServico;
  final double desconto;
  final double valorRecebido;

  final bool confirmado;
  final bool compareceu;
  final bool encaixe;

  final String? grupoAgendamentoId;
  final int ordemNoGrupo;

  final String observacoes;
  final String? formaPagamento;

  final String? consumoPrevistoJson;
  final String? consumoRealizadoJson;
  final bool estoqueConsumido;

  final DateTime dataCriacao;

  const AgendamentoRegistro({
    required this.id,
    required this.clienteId,
    required this.clienteNome,
    required this.profissionalId,
    required this.profissionalNome,
    required this.servicoId,
    required this.servicoNome,
    required this.inicio,
    required this.fim,
    required this.status,
    required this.valorServico,
    required this.desconto,
    required this.valorRecebido,
    required this.confirmado,
    required this.compareceu,
    this.encaixe = false,
    this.formaPagamento,
    this.grupoAgendamentoId,
    this.ordemNoGrupo = 0,
    this.observacoes = '',
    this.consumoPrevistoJson,
    this.consumoRealizadoJson,
    this.estoqueConsumido = false,
    required this.dataCriacao,
  });

  Map<String, Object?> paraMapa() {
    return {
      'id': id,
      'cliente_id': clienteId,
      'profissional_id': profissionalId,
      'servico_id': servicoId,
      'inicio': inicio.toIso8601String(),
      'fim': fim.toIso8601String(),
      'status': status,
      'valor_servico': valorServico,
      'desconto': desconto,
      'valor_recebido': valorRecebido,
      'confirmado': confirmado ? 1 : 0,
      'compareceu': compareceu ? 1 : 0,
      'encaixe': encaixe ? 1 : 0,
      'grupo_agendamento_id': grupoAgendamentoId,
      'ordem_no_grupo': ordemNoGrupo,
      'observacoes': observacoes,
      'consumo_previsto_json': consumoPrevistoJson,
      'consumo_realizado_json': consumoRealizadoJson,
      'estoque_consumido': estoqueConsumido ? 1 : 0,
      'data_criacao': dataCriacao.toIso8601String(),
    };
  }

  factory AgendamentoRegistro.doMapa(Map<String, Object?> mapa) {
    return AgendamentoRegistro(
      id: mapa['id'] as String,
      clienteId: mapa['cliente_id'] as String,
      clienteNome: mapa['cliente_nome'] as String? ?? 'Cliente',
      profissionalId: mapa['profissional_id'] as String,
      profissionalNome: mapa['profissional_nome'] as String? ?? 'Profissional',
      servicoId: mapa['servico_id'] as String,
      servicoNome: mapa['servico_nome'] as String? ?? 'Serviço',
      inicio: DateTime.parse(mapa['inicio'] as String),
      fim: DateTime.parse(mapa['fim'] as String),
      status: mapa['status'] as String? ?? 'agendado',
      valorServico: (mapa['valor_servico'] as num? ?? 0).toDouble(),
      desconto: (mapa['desconto'] as num? ?? 0).toDouble(),
      valorRecebido: (mapa['valor_recebido'] as num? ?? 0).toDouble(),
      confirmado: (mapa['confirmado'] as int? ?? 0) == 1,
      compareceu: (mapa['compareceu'] as int? ?? 0) == 1,
      encaixe: (mapa['encaixe'] as int? ?? 0) == 1,
      grupoAgendamentoId: mapa['grupo_agendamento_id'] as String?,
      ordemNoGrupo: (mapa['ordem_no_grupo'] as num?)?.toInt() ?? 0,
      observacoes: mapa['observacoes'] as String? ?? '',
      formaPagamento: mapa['forma_pagamento'] as String?,
      consumoPrevistoJson: mapa['consumo_previsto_json'] as String?,
      consumoRealizadoJson: mapa['consumo_realizado_json'] as String?,
      estoqueConsumido: (mapa['estoque_consumido'] as num?)?.toInt() == 1,
      dataCriacao: DateTime.parse(mapa['data_criacao'] as String),
    );
  }

  double get valorFinal {
    return valorServico - desconto;
  }

  bool get pagamentoPendente {
    return valorRecebido < valorFinal;
  }

  AgendamentoRegistro copiarCom({
    String? id,
    String? status,
    bool? confirmado,
    bool? compareceu,
    bool? encaixe,
    double? desconto,
    double? valorRecebido,
    String? observacoes,
    String? grupoAgendamentoId,
    int? ordemNoGrupo,
    DateTime? inicio,
    DateTime? fim,
  }) {
    return AgendamentoRegistro(
      id: id ?? this.id,
      clienteId: clienteId,
      clienteNome: clienteNome,
      profissionalId: profissionalId,
      profissionalNome: profissionalNome,
      servicoId: servicoId,
      servicoNome: servicoNome,
      inicio: inicio ?? this.inicio,
      fim: fim ?? this.fim,
      status: status ?? this.status,
      valorServico: valorServico,
      desconto: desconto ?? this.desconto,
      valorRecebido: valorRecebido ?? this.valorRecebido,
      confirmado: confirmado ?? this.confirmado,
      compareceu: compareceu ?? this.compareceu,
      encaixe: encaixe ?? this.encaixe,
      grupoAgendamentoId: grupoAgendamentoId ?? this.grupoAgendamentoId,
      ordemNoGrupo: ordemNoGrupo ?? this.ordemNoGrupo,
      observacoes: observacoes ?? this.observacoes,
      dataCriacao: dataCriacao,
    );
  }
}

class AgendaRepository {
  final DatabaseService _databaseService;

  AgendaRepository({DatabaseService? databaseService})
    : _databaseService = databaseService ?? DatabaseService.instance;

  String get _comercioId {
    final usuario = SessionController.instance.usuario;
    if (usuario == null || !usuario.podeAcao(AcaoPermissao.gerenciarAgenda)) {
      throw StateError('Você não possui permissão para gerenciar agenda.');
    }
    return usuario.comercioId;
  }

  Future<List<AgendamentoRegistro>> listarPorDia(DateTime data) async {
    final Database db = await _databaseService.database;

    final inicioDia = DateTime(data.year, data.month, data.day);

    final fimDia = inicioDia.add(const Duration(days: 1));

    final registros = await db.rawQuery(
      '''
      SELECT
        a.*,
        c.nome AS cliente_nome,
        p.nome AS profissional_nome,
        s.nome AS servico_nome
      FROM agendamentos a
      INNER JOIN clientes c
        ON c.id = a.cliente_id
      INNER JOIN profissionais p
        ON p.id = a.profissional_id
      INNER JOIN servicos s
        ON s.id = a.servico_id
      WHERE a.inicio >= ?
        AND a.inicio < ?
        AND a.comercio_id = ?
        AND a.excluido = 0
      ORDER BY a.inicio ASC
      ''',
      [inicioDia.toIso8601String(), fimDia.toIso8601String(), _comercioId],
    );

    return registros.map(AgendamentoRegistro.doMapa).toList();
  }

  Future<List<AgendamentoRegistro>> listarTodos() async {
    final Database db = await _databaseService.database;

    final registros = await db.rawQuery(
      '''
      SELECT
        a.*,
        c.nome AS cliente_nome,
        p.nome AS profissional_nome,
        s.nome AS servico_nome
      FROM agendamentos a
      INNER JOIN clientes c
        ON c.id = a.cliente_id
      INNER JOIN profissionais p
        ON p.id = a.profissional_id
      INNER JOIN servicos s
        ON s.id = a.servico_id
      WHERE a.comercio_id = ?
        AND a.excluido = 0
      ORDER BY a.inicio ASC
      ''',
      [_comercioId],
    );

    return registros.map(AgendamentoRegistro.doMapa).toList();
  }

  Future<List<AgendamentoRegistro>> listarPorGrupo(
    String grupoAgendamentoId,
  ) async {
    final Database db = await _databaseService.database;

    final registros = await db.rawQuery(
      '''
      SELECT
        a.*,
        c.nome AS cliente_nome,
        p.nome AS profissional_nome,
        s.nome AS servico_nome
      FROM agendamentos a
      INNER JOIN clientes c
        ON c.id = a.cliente_id
      INNER JOIN profissionais p
        ON p.id = a.profissional_id
      INNER JOIN servicos s
        ON s.id = a.servico_id
      WHERE a.comercio_id = ?
        AND a.grupo_agendamento_id = ?
        AND a.excluido = 0
      ORDER BY a.ordem_no_grupo ASC
      ''',
      [_comercioId, grupoAgendamentoId],
    );

    return registros.map(AgendamentoRegistro.doMapa).toList();
  }

  Future<void> inserir(AgendamentoRegistro agendamento) async {
    final Database db = await _databaseService.database;

    final possuiConflito = await verificarConflito(
      profissionalId: agendamento.profissionalId,
      inicio: agendamento.inicio,
      fim: agendamento.fim,
    );

    if (possuiConflito) {
      final agendaCompleta = AgendaCompletaRepository(
        databaseProvider: () => _databaseService.database,
        comercioId: _comercioId,
      );
      final duracaoMinutos = agendamento.fim
          .difference(agendamento.inicio)
          .inMinutes;
      final alternativas = await agendaCompleta.horariosDisponiveis(
        profissionalId: agendamento.profissionalId,
        data: agendamento.inicio,
        duracaoMinutos: duracaoMinutos,
      );
      throw ConflitoAgendaException(
        'Já existe um agendamento nesse horário para essa profissional.',
        alternativas,
      );
    }

    await db.transaction((txn) async {
      final consumoPrevisto = await _calcularConsumoPrevisto(
        txn,
        agendamento.servicoId,
      );

      await txn.insert('agendamentos', {
        ...agendamento.paraMapa(),
        'consumo_previsto_json': consumoPrevisto,
        'comercio_id': _comercioId,
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      await _enfileirarWhatsapp(txn, agendamento);
    });
  }

  Future<void> inserirGrupo(
    AgendamentoGrupoRegistro grupo,
    List<AgendamentoRegistro> agendamentos,
  ) async {
    final Database db = await _databaseService.database;

    // Buscar todos os agendamentos existentes no dia para os profissionais envolvidos
    final profissionalIds = agendamentos.map((e) => e.profissionalId).toSet();
    final inicioMenor = agendamentos
        .map((e) => e.inicio)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final fimMaior = agendamentos
        .map((e) => e.fim)
        .reduce((a, b) => a.isAfter(b) ? a : b);

    final inicioDia = DateTime(
      inicioMenor.year,
      inicioMenor.month,
      inicioMenor.day,
    );
    final fimDia = DateTime(
      fimMaior.year,
      fimMaior.month,
      fimMaior.day,
    ).add(const Duration(days: 1));

    final profIdsParams = profissionalIds.map((_) => '?').join(',');
    final args = [
      _comercioId,
      inicioDia.toIso8601String(),
      fimDia.toIso8601String(),
      ...profissionalIds,
    ];

    final registrosDb = await db.rawQuery('''
      SELECT a.*, c.nome AS cliente_nome, p.nome AS profissional_nome, s.nome AS servico_nome
      FROM agendamentos a
      INNER JOIN clientes c ON c.id = a.cliente_id
      INNER JOIN profissionais p ON p.id = a.profissional_id
      INNER JOIN servicos s ON s.id = a.servico_id
      WHERE a.comercio_id = ?
        AND a.excluido = 0
        AND a.inicio >= ?
        AND a.inicio < ?
        AND a.profissional_id IN ($profIdsParams)
      ''', args);

    final existentes = registrosDb.map(AgendamentoRegistro.doMapa).toList();

    // Validação pura do conflito
    AgendaConflictChecker.validar(novos: agendamentos, existentes: existentes);

    // Inserção atômica
    await db.transaction((txn) async {
      // 1. Inserir grupo
      await txn.insert('agendamento_grupos', {
        'id': grupo.id,
        'business_id': _comercioId,
        'cliente_id': grupo.clienteId,
        'comanda_id': grupo.comandaId,
        'status': grupo.status,
        'observacoes': grupo.observacoes,
        'created_at': grupo.createdAt.toIso8601String(),
        'updated_at': grupo.updatedAt.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      // 2. Inserir cada serviço associado
      for (var item in agendamentos) {
        final consumoPrevisto = await _calcularConsumoPrevisto(
          txn,
          item.servicoId,
        );

        await txn.insert('agendamentos', {
          ...item.paraMapa(),
          'consumo_previsto_json': consumoPrevisto,
          'comercio_id': _comercioId,
        }, conflictAlgorithm: ConflictAlgorithm.abort);

        await _enfileirarWhatsapp(txn, item);
      }
    });
  }

  Future<void> _enfileirarWhatsapp(
    Transaction txn,
    AgendamentoRegistro agendamento,
  ) async {
    final cliente = await txn.query(
      'clientes',
      columns: ['whatsapp'],
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [agendamento.clienteId, _comercioId],
    );

    if (cliente.isNotEmpty) {
      final whatsapp = cliente.first['whatsapp'] as String?;
      if (whatsapp != null && whatsapp.isNotEmpty) {
        await WhatsappQueueService().enfileirar(
          txn: txn,
          comercioId: _comercioId,
          destinatario: whatsapp,
          template: 'agendamento_criado',
          payload: agendamento.paraMapa(),
          agendamentoId: agendamento.id,
        );
      }
    }
  }

  Future<String?> _calcularConsumoPrevisto(
    Transaction txn,
    String servicoId,
  ) async {
    final materiais = await txn.query(
      'servico_materiais',
      where: 'servico_id = ? AND comercio_id = ?',
      whereArgs: [servicoId, _comercioId],
    );
    if (materiais.isEmpty) return null;

    final listaJson = materiais.map((m) {
      return {
        'produto_id': m['estoque_id'],
        'quantidade': m['quantidade'],
        'unidade': m['unidade_medida'],
      };
    }).toList();

    return jsonEncode(listaJson);
  }

  Future<void> atualizar(AgendamentoRegistro agendamento) async {
    final Database db = await _databaseService.database;

    final possuiConflito = await verificarConflito(
      profissionalId: agendamento.profissionalId,
      inicio: agendamento.inicio,
      fim: agendamento.fim,
      ignorarAgendamentoId: agendamento.id,
    );

    if (possuiConflito) {
      final agendaCompleta = AgendaCompletaRepository(
        databaseProvider: () => _databaseService.database,
        comercioId: _comercioId,
      );
      final duracaoMinutos = agendamento.fim
          .difference(agendamento.inicio)
          .inMinutes;
      final alternativas = await agendaCompleta.horariosDisponiveis(
        profissionalId: agendamento.profissionalId,
        data: agendamento.inicio,
        duracaoMinutos: duracaoMinutos,
      );
      throw ConflitoAgendaException(
        'Já existe outro agendamento nesse horário.',
        alternativas,
      );
    }

    final quantidadeAlterada = await db.update(
      'agendamentos',
      agendamento.paraMapa(),
      where: 'id = ? AND comercio_id = ? AND excluido = 0',
      whereArgs: [agendamento.id, _comercioId],
    );

    if (quantidadeAlterada == 0) {
      throw StateError('Agendamento não encontrado.');
    }
  }

  Future<void> remarcarGrupo(
    String grupoAgendamentoId,
    DateTime novoInicio,
  ) async {
    final Database db = await _databaseService.database;
    final grupo = await listarPorGrupo(grupoAgendamentoId);
    if (grupo.isEmpty) throw StateError('Grupo não encontrado.');

    // Encontrar o menor inicio atual para calcular a diferença
    final inicioMenor = grupo
        .map((e) => e.inicio)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final offset = novoInicio.difference(inicioMenor);

    // Ajustar todos os agendamentos do grupo com o mesmo offset
    final grupoAtualizado = grupo.map((e) {
      return e.copiarCom(inicio: e.inicio.add(offset), fim: e.fim.add(offset));
    }).toList();

    // Validar conflitos puros
    // (Apenas buscaríamos existentes se estivéssemos no método de inserirGrupo;
    // aqui para simplificar, vamos reutilizar a mesma lógica de busca de existentes
    // mas com os novos horários)

    final profissionalIds = grupoAtualizado
        .map((e) => e.profissionalId)
        .toSet();
    final inicioMenorAtualizado = novoInicio;
    final fimMaiorAtualizado = grupoAtualizado
        .map((e) => e.fim)
        .reduce((a, b) => a.isAfter(b) ? a : b);

    final inicioDia = DateTime(
      inicioMenorAtualizado.year,
      inicioMenorAtualizado.month,
      inicioMenorAtualizado.day,
    );
    final fimDia = DateTime(
      fimMaiorAtualizado.year,
      fimMaiorAtualizado.month,
      fimMaiorAtualizado.day,
    ).add(const Duration(days: 1));

    final profIdsParams = profissionalIds.map((_) => '?').join(',');
    final args = [
      _comercioId,
      inicioDia.toIso8601String(),
      fimDia.toIso8601String(),
      ...profissionalIds,
    ];

    final registrosDb = await db.rawQuery('''
      SELECT a.*, c.nome AS cliente_nome, p.nome AS profissional_nome, s.nome AS servico_nome
      FROM agendamentos a
      INNER JOIN clientes c ON c.id = a.cliente_id
      INNER JOIN profissionais p ON p.id = a.profissional_id
      INNER JOIN servicos s ON s.id = a.servico_id
      WHERE a.comercio_id = ?
        AND a.excluido = 0
        AND a.inicio >= ?
        AND a.inicio < ?
        AND a.profissional_id IN ($profIdsParams)
      ''', args);
    final existentes = registrosDb.map(AgendamentoRegistro.doMapa).toList();

    AgendaConflictChecker.validar(
      novos: grupoAtualizado,
      existentes: existentes,
      ignoredAppointmentIds: grupoAtualizado.map((e) => e.id).toSet(),
    );

    await db.transaction((txn) async {
      for (var item in grupoAtualizado) {
        await txn.update(
          'agendamentos',
          item.paraMapa(),
          where: 'id = ? AND comercio_id = ?',
          whereArgs: [item.id, _comercioId],
        );
      }
    });
  }

  Future<void> cancelarGrupo(String grupoAgendamentoId) async {
    final Database db = await _databaseService.database;
    final grupo = await listarPorGrupo(grupoAgendamentoId);
    if (grupo.isEmpty) return;

    await db.transaction((txn) async {
      for (var item in grupo) {
        await txn.update(
          'agendamentos',
          {'status': 'cancelado'},
          where: 'id = ? AND comercio_id = ? AND excluido = 0',
          whereArgs: [item.id, _comercioId],
        );
      }

      await txn.update(
        'agendamento_grupos',
        {'status': 'cancelado', 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ? AND business_id = ?',
        whereArgs: [grupoAgendamentoId, _comercioId],
      );
    });
  }

  Future<void> atualizarStatus({
    required String agendamentoId,
    required String status,
    bool? confirmado,
    bool? compareceu,
    bool? encaixe,
  }) async {
    final Database db = await _databaseService.database;

    final dados = <String, Object?>{'status': status};

    if (confirmado != null) {
      dados['confirmado'] = confirmado ? 1 : 0;
    }

    if (compareceu != null) {
      dados['compareceu'] = compareceu ? 1 : 0;
    }

    await db.update(
      'agendamentos',
      dados,
      where: 'id = ? AND comercio_id = ? AND excluido = 0',
      whereArgs: [agendamentoId, _comercioId],
    );
  }

  @Deprecated(
    'Use AgendaCompletaRepository.excluirSeguro com motivo e auditoria',
  )
  Future<void> excluir(String agendamentoId) async {
    throw UnsupportedError(
      'Exclusão direta desativada. Use a exclusão segura com motivo e auditoria.',
    );
  }

  Future<bool> verificarConflito({
    required String profissionalId,
    required DateTime inicio,
    required DateTime fim,
    String? ignorarAgendamentoId,
  }) async {
    final Database db = await _databaseService.database;

    String where = '''
      comercio_id = ?
      AND profissional_id = ?
      AND status != ?
      AND excluido = 0
      AND inicio < ?
      AND fim > ?
    ''';

    final whereArgs = <Object?>[
      _comercioId,
      profissionalId,
      'cancelado',
      fim.toIso8601String(),
      inicio.toIso8601String(),
    ];

    if (ignorarAgendamentoId != null) {
      where += ' AND id != ?';
      whereArgs.add(ignorarAgendamentoId);
    }

    final registros = await db.query(
      'agendamentos',
      columns: ['id'],
      where: where,
      whereArgs: whereArgs,
      limit: 1,
    );

    return registros.isNotEmpty;
  }

  Future<AgendamentoRegistro?> buscarPorId(String agendamentoId) async {
    final Database db = await _databaseService.database;

    final registros = await db.rawQuery(
      '''
      SELECT
        a.*,
        c.nome AS cliente_nome,
        p.nome AS profissional_nome,
        s.nome AS servico_nome
      FROM agendamentos a
      INNER JOIN clientes c
        ON c.id = a.cliente_id
      INNER JOIN profissionais p
        ON p.id = a.profissional_id
      INNER JOIN servicos s
        ON s.id = a.servico_id
      WHERE a.id = ? AND a.comercio_id = ? AND a.excluido = 0
      LIMIT 1
      ''',
      [agendamentoId, _comercioId],
    );

    if (registros.isEmpty) {
      return null;
    }

    return AgendamentoRegistro.doMapa(registros.first);
  }

  Future<void> concluirAtendimentoComEstoque({
    required String agendamentoId,
    required double valorRecebido,
    required List<Map<String, dynamic>> consumoEfetivo,
    required String profissionalId,
  }) async {
    final Database db = await _databaseService.database;

    await db.transaction((txn) async {
      final agendamentoRow = await txn.query(
        'agendamentos',
        where: 'id = ? AND comercio_id = ? AND excluido = 0',
        whereArgs: [agendamentoId, _comercioId],
      );

      if (agendamentoRow.isEmpty) {
        throw StateError('Agendamento nÃ£o encontrado.');
      }

      final agendamento = agendamentoRow.first;
      final bool estoqueConsumido =
          (agendamento['estoque_consumido'] as num?)?.toInt() == 1;

      if (!estoqueConsumido) {
        for (final item in consumoEfetivo) {
          final produtoId = item['produto_id'] as String;
          final quantidade = (item['quantidade'] as num).toDouble();

          if (quantidade <= 0) continue;

          final saldoAtual = await txn.query(
            'estoque_saldos',
            columns: ['quantidade_atual'],
            where: 'estoque_id = ? AND business_id = ? AND finalidade = ?',
            whereArgs: [produtoId, _comercioId, 'uso_interno'],
          );

          final qteAnterior = saldoAtual.isNotEmpty
              ? (saldoAtual.first['quantidade_atual'] as num).toDouble()
              : 0.0;
          final qtePosterior = qteAnterior - quantidade;

          final idempotencyKey =
              '${_comercioId}_${agendamentoId}_${produtoId}_uso_interno';

          final mov = await txn.query(
            'movimentacoes_estoque',
            columns: ['id'],
            where: 'idempotency_key = ?',
            whereArgs: [idempotencyKey],
          );

          if (mov.isEmpty) {
            await txn.insert('movimentacoes_estoque', {
              'id':
                  '${DateTime.now().microsecondsSinceEpoch}_$produtoId',
              'item_estoque_id': produtoId,
              'tipo': 'saida',
              'finalidade': 'uso_interno',
              'quantidade': quantidade,
              'quantidade_anterior': qteAnterior,
              'quantidade_posterior': qtePosterior,
              'data': DateTime.now().toIso8601String(),
              'motivo': 'Consumo no atendimento',
              'agendamento_id': agendamentoId,
              'profissional_id': profissionalId,
              'idempotency_key': idempotencyKey,
            });

            if (saldoAtual.isEmpty) {
              await txn.insert('estoque_saldos', {
                'id':
                    '${DateTime.now().microsecondsSinceEpoch}_$produtoId',
                'business_id': _comercioId,
                'estoque_id': produtoId,
                'finalidade': 'uso_interno',
                'quantidade_atual': qtePosterior,
                'created_at': DateTime.now().toIso8601String(),
                'updated_at': DateTime.now().toIso8601String(),
              });
            } else {
              await txn.update(
                'estoque_saldos',
                {
                  'quantidade_atual': qtePosterior,
                  'updated_at': DateTime.now().toIso8601String(),
                },
                where: 'estoque_id = ? AND business_id = ? AND finalidade = ?',
                whereArgs: [produtoId, _comercioId, 'uso_interno'],
              );
            }
          }
        }
      }

      final consumoRealizadoJson = jsonEncode(consumoEfetivo);

      await txn.update(
        'agendamentos',
        {
          'status': 'concluido',
          'confirmado': 1,
          'compareceu': 1,
          'valor_recebido': valorRecebido,
          'estoque_consumido': 1,
          'consumo_realizado_json': consumoRealizadoJson,
        },
        where: 'id = ? AND comercio_id = ? AND excluido = 0',
        whereArgs: [agendamentoId, _comercioId],
      );

      // Suporte legado
      if (agendamento['pacote_venda_sessao_id'] != null) {
        // Isso invoca outra connection fora da transaÃ§Ã£o. NÃ£o Ã© o ideal.
        // Na Etapa 4.4 removeremos pacote_venda_sessao_id daqui.
        PacotesRepository().concluirAgendamentoPacote(agendamentoId).ignore();
      }
    });
  }

  Future<void> concluirAgendamento({
    required String agendamentoId,
    required double valorRecebido,
  }) async {
    final Database db = await _databaseService.database;

    final pacote = await db.query(
      'agendamentos',
      columns: ['forma_pagamento'],
      where: 'id = ? AND comercio_id = ? AND excluido = 0',
      whereArgs: [agendamentoId, _comercioId],
      limit: 1,
    );
    if (pacote.isNotEmpty && pacote.first['forma_pagamento'] == 'Pacote') {
      await PacotesRepository().concluirAgendamentoPacote(agendamentoId);
      return;
    }

    await db.update(
      'agendamentos',
      {
        'status': 'concluido',
        'confirmado': 1,
        'compareceu': 1,
        'valor_recebido': valorRecebido,
      },
      where: 'id = ? AND comercio_id = ? AND excluido = 0',
      whereArgs: [agendamentoId, _comercioId],
    );
  }

  Future<void> confirmarAgendamento(String agendamentoId) async {
    final Database db = await _databaseService.database;

    await db.update(
      'agendamentos',
      {'status': 'confirmado', 'confirmado': 1},
      where: 'id = ? AND comercio_id = ? AND excluido = 0',
      whereArgs: [agendamentoId, _comercioId],
    );
  }

  @Deprecated('Use AgendaCompletaRepository.registrarStatus com motivo')
  Future<void> cancelarAgendamento(String agendamentoId) async {
    throw UnsupportedError(
      'Cancelamento direto desativado. Informe o motivo no fluxo seguro.',
    );
  }
}
