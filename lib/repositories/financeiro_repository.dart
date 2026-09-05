import 'package:sqflite/sqflite.dart';

import '../database/database_service.dart';
import '../models/domain/acesso.dart';
import '../services/session_controller.dart';
import 'notification_center_repository.dart';

class MovimentacaoFinanceiraRegistro {
  final String id;
  final String tipo;
  final String descricao;
  final double valor;
  final String formaPagamento;
  final String status;
  final DateTime data;
  final DateTime dataCriacao;
  final String categoria;
  final String? clienteId;
  final String? profissionalId;
  final String? agendamentoId;
  final String? servicoId;
  final String? usuarioResponsavelId;
  final String observacoes;
  final String? centroResultado;
  final String? entidadeOrigem;
  final String? entidadeOrigemId;

  const MovimentacaoFinanceiraRegistro({
    required this.id,
    required this.tipo,
    required this.descricao,
    required this.valor,
    required this.formaPagamento,
    required this.status,
    required this.data,
    required this.dataCriacao,
    required this.categoria,
    required this.clienteId,
    required this.profissionalId,
    required this.agendamentoId,
    required this.servicoId,
    required this.usuarioResponsavelId,
    required this.observacoes,
    this.centroResultado,
    this.entidadeOrigem,
    this.entidadeOrigemId,
  });

  bool get ehEntrada {
    return tipo == 'entrada' || tipo == 'receita';
  }

  bool get ehSaida {
    return tipo == 'saida' || tipo == 'despesa';
  }

  bool get pago {
    return status == 'pago';
  }

  bool get pendente {
    return status == 'pendente';
  }

  Map<String, Object?> paraMapa() {
    return {
      'id': id,
      'tipo': tipo,
      'descricao': descricao,
      'valor': valor,
      'forma_pagamento': formaPagamento.isEmpty ? null : formaPagamento,
      'status': status,
      'data': data.toIso8601String(),
      'data_criacao': dataCriacao.toIso8601String(),
      'categoria': categoria.isEmpty ? null : categoria,
      'cliente_id': clienteId,
      'profissional_id': profissionalId,
      'agendamento_id': agendamentoId,
      'servico_id': servicoId,
      'usuario_responsavel_id': usuarioResponsavelId,
      'observacoes': observacoes,
      'centro_resultado': centroResultado,
      'entidade_origem': entidadeOrigem,
      'entidade_origem_id': entidadeOrigemId,
    };
  }

  factory MovimentacaoFinanceiraRegistro.doMapa(Map<String, Object?> mapa) {
    return MovimentacaoFinanceiraRegistro(
      id: mapa['id'] as String,
      tipo: mapa['tipo'] as String? ?? 'entrada',
      descricao: mapa['descricao'] as String? ?? 'Movimentação',
      valor: (mapa['valor'] as num? ?? 0).toDouble(),
      formaPagamento: mapa['forma_pagamento'] as String? ?? '',
      status: mapa['status'] as String? ?? 'pago',
      data: DateTime.tryParse(mapa['data'] as String? ?? '') ?? DateTime.now(),
      dataCriacao:
          DateTime.tryParse(mapa['data_criacao'] as String? ?? '') ??
          DateTime.now(),
      categoria: mapa['categoria'] as String? ?? 'Outros',
      clienteId: mapa['cliente_id'] as String?,
      profissionalId: mapa['profissional_id'] as String?,
      agendamentoId: mapa['agendamento_id'] as String?,
      servicoId: mapa['servico_id'] as String?,
      usuarioResponsavelId: mapa['usuario_responsavel_id'] as String?,
      observacoes: mapa['observacoes'] as String? ?? '',
      centroResultado: mapa['centro_resultado'] as String?,
      entidadeOrigem: mapa['entidade_origem'] as String?,
      entidadeOrigemId: mapa['entidade_origem_id'] as String?,
    );
  }

  MovimentacaoFinanceiraRegistro copiarCom({
    String? tipo,
    String? descricao,
    double? valor,
    String? formaPagamento,
    String? status,
    DateTime? data,
    String? categoria,
    String? clienteId,
    String? profissionalId,
    String? agendamentoId,
    String? servicoId,
    String? usuarioResponsavelId,
    String? observacoes,
  }) {
    return MovimentacaoFinanceiraRegistro(
      id: id,
      tipo: tipo ?? this.tipo,
      descricao: descricao ?? this.descricao,
      valor: valor ?? this.valor,
      formaPagamento: formaPagamento ?? this.formaPagamento,
      status: status ?? this.status,
      data: data ?? this.data,
      dataCriacao: dataCriacao,
      categoria: categoria ?? this.categoria,
      clienteId: clienteId ?? this.clienteId,
      profissionalId: profissionalId ?? this.profissionalId,
      agendamentoId: agendamentoId ?? this.agendamentoId,
      servicoId: servicoId ?? this.servicoId,
      usuarioResponsavelId: usuarioResponsavelId ?? this.usuarioResponsavelId,
      observacoes: observacoes ?? this.observacoes,
      centroResultado: centroResultado,
      entidadeOrigem: entidadeOrigem,
      entidadeOrigemId: entidadeOrigemId,
    );
  }
}

class ResumoFinanceiro {
  final double totalEntradas;
  final double totalSaidas;
  final double saldo;
  final double contasReceber;
  final double contasPagar;
  final int quantidadeEntradas;
  final int quantidadeSaidas;
  final int quantidadePendentes;

  const ResumoFinanceiro({
    required this.totalEntradas,
    required this.totalSaidas,
    required this.saldo,
    required this.contasReceber,
    required this.contasPagar,
    required this.quantidadeEntradas,
    required this.quantidadeSaidas,
    required this.quantidadePendentes,
  });

  factory ResumoFinanceiro.vazio() {
    return const ResumoFinanceiro(
      totalEntradas: 0,
      totalSaidas: 0,
      saldo: 0,
      contasReceber: 0,
      contasPagar: 0,
      quantidadeEntradas: 0,
      quantidadeSaidas: 0,
      quantidadePendentes: 0,
    );
  }
}

class ResumoCategoriaFinanceira {
  final String categoria;
  final double total;
  final int quantidade;

  const ResumoCategoriaFinanceira({
    required this.categoria,
    required this.total,
    required this.quantidade,
  });

  factory ResumoCategoriaFinanceira.doMapa(Map<String, Object?> mapa) {
    return ResumoCategoriaFinanceira(
      categoria: mapa['categoria'] as String? ?? 'Outros',
      total: (mapa['total'] as num? ?? 0).toDouble(),
      quantidade: (mapa['quantidade'] as num? ?? 0).toInt(),
    );
  }
}

class FinanceiroRepository {
  Future<void> _agendarNotificacoesFinanceiras(
    MovimentacaoFinanceiraRegistro mov,
  ) async {
    final notifications = NotificationCenterRepository(
      databaseProvider: () => _databaseService.database,
      businessId: _comercioId,
    );

    if (mov.status != 'pendente') {
      await notifications.cancelEntity('financial_movement', mov.id);
      return;
    }

    final dataVencimento = mov.data;
    final scheduledDate = DateTime(
      dataVencimento.year,
      dataVencimento.month,
      dataVencimento.day,
      8,
    );
    await notifications.cancelEntity('financial_movement', mov.id);
    await notifications.schedule(
      key: 'financial:${mov.id}:due',
      type: mov.tipo == 'entrada'
          ? 'financeiro_recebimento_vencendo'
          : 'financeiro_pagamento_pendente',
      category: 'financeiro',
      entity: 'financial_movement',
      entityId: mov.id,
      title: mov.tipo == 'entrada'
          ? 'Conta a receber vencendo'
          : 'Pagamento pendente',
      body: '${mov.descricao} — R\$ ${mov.valor.toStringAsFixed(2)}',
      date: scheduledDate,
      route: '/financeiro/${mov.id}',
      priority: 'alta',
    );
  }

  final DatabaseService _databaseService;

  FinanceiroRepository({DatabaseService? databaseService})
    : _databaseService = databaseService ?? DatabaseService.instance;

  String get _comercioId {
    final usuario = SessionController.instance.usuario;
    if (usuario == null || !usuario.podeAcao(AcaoPermissao.acessarFinanceiro)) {
      throw StateError('Você não possui permissão para acessar financeiro.');
    }
    return usuario.comercioId;
  }

  Future<List<MovimentacaoFinanceiraRegistro>> listar({
    DateTime? dataInicial,
    DateTime? dataFinal,
    String? tipo,
    String? status,
    String? categoria,
    int limite = 500,
  }) async {
    final Database db = await _databaseService.database;

    final condicoes = <String>['comercio_id = ?'];
    final argumentos = <Object?>[_comercioId];

    if (dataInicial != null) {
      condicoes.add('data >= ?');

      argumentos.add(
        DateTime(
          dataInicial.year,
          dataInicial.month,
          dataInicial.day,
        ).toIso8601String(),
      );
    }

    if (dataFinal != null) {
      condicoes.add('data < ?');

      argumentos.add(
        DateTime(
          dataFinal.year,
          dataFinal.month,
          dataFinal.day + 1,
        ).toIso8601String(),
      );
    }

    if (tipo != null && tipo.isNotEmpty && tipo != 'todos') {
      condicoes.add('tipo = ?');
      argumentos.add(tipo);
    }

    if (status != null && status.isNotEmpty && status != 'todos') {
      condicoes.add('status = ?');
      argumentos.add(status);
    }

    if (categoria != null && categoria.isNotEmpty && categoria != 'todas') {
      condicoes.add('categoria = ?');
      argumentos.add(categoria);
    }

    final registros = await db.query(
      'movimentacoes_financeiras',
      where: condicoes.join(' AND '),
      whereArgs: argumentos,
      orderBy: 'data DESC, data_criacao DESC',
      limit: limite,
    );

    return registros.map(MovimentacaoFinanceiraRegistro.doMapa).toList();
  }

  Future<MovimentacaoFinanceiraRegistro?> buscarPorId(String id) async {
    final Database db = await _databaseService.database;

    final registros = await db.query(
      'movimentacoes_financeiras',
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [id, _comercioId],
      limit: 1,
    );

    if (registros.isEmpty) {
      return null;
    }

    return MovimentacaoFinanceiraRegistro.doMapa(registros.first);
  }

  Future<void> inserir(MovimentacaoFinanceiraRegistro movimentacao) async {
    final Database db = await _databaseService.database;

    await db.insert('movimentacoes_financeiras', {
      ...movimentacao.paraMapa(),
      'comercio_id': _comercioId,
    }, conflictAlgorithm: ConflictAlgorithm.abort);

    await _agendarNotificacoesFinanceiras(movimentacao);
  }

  Future<void> atualizar(MovimentacaoFinanceiraRegistro movimentacao) async {
    final Database db = await _databaseService.database;

    final quantidadeAlterada = await db.update(
      'movimentacoes_financeiras',
      movimentacao.paraMapa(),
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [movimentacao.id, _comercioId],
    );

    if (quantidadeAlterada == 0) {
      throw StateError('Movimentação financeira não encontrada.');
    }

    await _agendarNotificacoesFinanceiras(movimentacao);
  }

  Future<void> salvar(MovimentacaoFinanceiraRegistro movimentacao) async {
    final existente = await buscarPorId(movimentacao.id);

    if (existente == null) {
      await inserir(movimentacao);
      return;
    }

    await atualizar(movimentacao);
  }

  Future<void> excluir(String id) async {
    final Database db = await _databaseService.database;

    await db.delete(
      'movimentacoes_financeiras',
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [id, _comercioId],
    );

    await NotificationCenterRepository(
      databaseProvider: () => _databaseService.database,
      businessId: _comercioId,
    ).cancelEntity('financial_movement', id);
  }

  Future<double> totalEntradas() async {
    final Database db = await _databaseService.database;

    final resultado = await db.rawQuery(
      '''
      SELECT SUM(valor) AS total
      FROM movimentacoes_financeiras
      WHERE
        (tipo = 'entrada'
         OR tipo = 'receita')
        AND status = 'pago'
        AND comercio_id = ?
      ''',
      [_comercioId],
    );

    return (resultado.first['total'] as num? ?? 0).toDouble();
  }

  Future<double> totalSaidas() async {
    final Database db = await _databaseService.database;

    final resultado = await db.rawQuery(
      '''
      SELECT SUM(valor) AS total
      FROM movimentacoes_financeiras
      WHERE
        (tipo = 'saida'
         OR tipo = 'despesa')
        AND status = 'pago'
        AND comercio_id = ?
      ''',
      [_comercioId],
    );

    return (resultado.first['total'] as num? ?? 0).toDouble();
  }

  Future<double> saldoAtual() async {
    final entradas = await totalEntradas();

    final saidas = await totalSaidas();

    return entradas - saidas;
  }

  Future<ResumoFinanceiro> resumo() async {
    final Database db = await _databaseService.database;

    final registros = await db.query(
      'movimentacoes_financeiras',
      where: 'comercio_id = ?',
      whereArgs: [_comercioId],
    );

    double entradas = 0;
    double saidas = 0;
    double receber = 0;
    double pagar = 0;

    int qtdEntradas = 0;
    int qtdSaidas = 0;
    int pendentes = 0;

    for (final item in registros) {
      final valor = (item['valor'] as num? ?? 0).toDouble();

      final tipo = item['tipo'] as String? ?? '';

      final status = item['status'] as String? ?? 'pago';

      if (tipo == 'entrada' || tipo == 'receita') {
        qtdEntradas++;

        if (status == 'pago') {
          entradas += valor;
        } else {
          receber += valor;
          pendentes++;
        }
      }

      if (tipo == 'saida' || tipo == 'despesa') {
        qtdSaidas++;

        if (status == 'pago') {
          saidas += valor;
        } else {
          pagar += valor;
          pendentes++;
        }
      }
    }

    return ResumoFinanceiro(
      totalEntradas: entradas,
      totalSaidas: saidas,
      saldo: entradas - saidas,
      contasReceber: receber,
      contasPagar: pagar,
      quantidadeEntradas: qtdEntradas,
      quantidadeSaidas: qtdSaidas,
      quantidadePendentes: pendentes,
    );
  }

  Future<List<ResumoCategoriaFinanceira>> resumoPorCategoria({
    String? tipo,
  }) async {
    final Database db = await _databaseService.database;

    String where = 'WHERE comercio_id = ?';

    final argumentos = <Object?>[_comercioId];

    if (tipo != null && tipo.isNotEmpty && tipo != 'todos') {
      where += ' AND tipo = ?';
      argumentos.add(tipo);
    }

    final resultado = await db.rawQuery('''
      SELECT
        COALESCE(categoria,'Outros') AS categoria,
        SUM(valor) AS total,
        COUNT(*) AS quantidade
      FROM movimentacoes_financeiras
      $where
      GROUP BY categoria
      ORDER BY total DESC
      ''', argumentos);

    return resultado.map(ResumoCategoriaFinanceira.doMapa).toList();
  }

  Future<List<String>> listarCategorias() async {
    final Database db = await _databaseService.database;

    final resultado = await db.rawQuery(
      '''
      SELECT DISTINCT categoria
      FROM movimentacoes_financeiras
      WHERE categoria IS NOT NULL
        AND categoria != ''
        AND comercio_id = ?
      ORDER BY categoria COLLATE NOCASE ASC
      ''',
      [_comercioId],
    );

    return resultado.map((item) => item['categoria'] as String).toList();
  }

  Future<void> alterarStatus({
    required String id,
    required String status,
  }) async {
    final Database db = await _databaseService.database;

    await db.update(
      'movimentacoes_financeiras',
      {'status': status},
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [id, _comercioId],
    );
  }

  Future<List<MovimentacaoFinanceiraRegistro>> movimentacoesHoje() async {
    final agora = DateTime.now();

    return listar(
      dataInicial: DateTime(agora.year, agora.month, agora.day),
      dataFinal: DateTime(agora.year, agora.month, agora.day),
    );
  }

  Future<List<MovimentacaoFinanceiraRegistro>> movimentacoesMesAtual() async {
    final agora = DateTime.now();

    return listar(
      dataInicial: DateTime(agora.year, agora.month, 1),
      dataFinal: DateTime(agora.year, agora.month + 1, 0),
    );
  }

  Future<int> quantidadeRegistros() async {
    final Database db = await _databaseService.database;

    final resultado = await db.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM movimentacoes_financeiras WHERE comercio_id = ?
      ''',
      [_comercioId],
    );

    return (resultado.first['total'] as num? ?? 0).toInt();
  }

  Future<void> limparTudo() async {
    final Database db = await _databaseService.database;

    await db.delete(
      'movimentacoes_financeiras',
      where: 'comercio_id = ?',
      whereArgs: [_comercioId],
    );
  }
}
