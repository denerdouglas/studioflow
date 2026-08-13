import 'package:sqflite/sqflite.dart';

import '../database/database_service.dart';
import '../services/session_controller.dart';

class MovimentoFinanceiroRegistro {
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

  const MovimentoFinanceiroRegistro({
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

  bool get entrada {
    return tipo == 'entrada';
  }

  bool get saida {
    return tipo == 'saida';
  }

  bool get pago {
    return status == 'pago';
  }

  Map<String, Object?> paraMapa() {
    return {
      'id': id,
      'tipo': tipo,
      'descricao': descricao,
      'valor': valor,
      'forma_pagamento': formaPagamento,
      'status': status,
      'data': data.toIso8601String(),
      'data_criacao': dataCriacao.toIso8601String(),
      'categoria': categoria,
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

  factory MovimentoFinanceiroRegistro.doMapa(Map<String, Object?> mapa) {
    return MovimentoFinanceiroRegistro(
      id: mapa['id'] as String,
      tipo: mapa['tipo'] as String? ?? 'entrada',
      descricao: mapa['descricao'] as String? ?? 'Movimentação',
      valor: (mapa['valor'] as num? ?? 0).toDouble(),
      formaPagamento: mapa['forma_pagamento'] as String? ?? 'Não informado',
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

  MovimentoFinanceiroRegistro copiarCom({
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
    return MovimentoFinanceiroRegistro(
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

class ResumoCaixa {
  final double totalEntradas;
  final double totalSaidas;
  final double saldo;
  final int quantidadeEntradas;
  final int quantidadeSaidas;

  const ResumoCaixa({
    required this.totalEntradas,
    required this.totalSaidas,
    required this.saldo,
    required this.quantidadeEntradas,
    required this.quantidadeSaidas,
  });

  factory ResumoCaixa.vazio() {
    return const ResumoCaixa(
      totalEntradas: 0,
      totalSaidas: 0,
      saldo: 0,
      quantidadeEntradas: 0,
      quantidadeSaidas: 0,
    );
  }
}

class CaixaRepository {
  final DatabaseService _databaseService;

  CaixaRepository({DatabaseService? databaseService})
    : _databaseService = databaseService ?? DatabaseService.instance;

  String get _comercioId => SessionController.instance.usuario!.comercioId;

  Future<List<MovimentoFinanceiroRegistro>> listarPorPeriodo({
    required DateTime inicio,
    required DateTime fim,
  }) async {
    final Database db = await _databaseService.database;

    final registros = await db.query(
      'movimentacoes_financeiras',
      where: 'data >= ? AND data < ? AND comercio_id = ?',
      whereArgs: [inicio.toIso8601String(), fim.toIso8601String(), _comercioId],
      orderBy: 'data DESC, data_criacao DESC',
    );

    return registros.map(MovimentoFinanceiroRegistro.doMapa).toList();
  }

  Future<List<MovimentoFinanceiroRegistro>> listarPorDia(DateTime data) async {
    final inicio = DateTime(data.year, data.month, data.day);

    final fim = inicio.add(const Duration(days: 1));

    return listarPorPeriodo(inicio: inicio, fim: fim);
  }

  Future<List<MovimentoFinanceiroRegistro>> listarPorMes(DateTime data) async {
    final inicio = DateTime(data.year, data.month, 1);

    final fim = data.month == 12
        ? DateTime(data.year + 1, 1, 1)
        : DateTime(data.year, data.month + 1, 1);

    return listarPorPeriodo(inicio: inicio, fim: fim);
  }

  Future<void> inserir(MovimentoFinanceiroRegistro movimento) async {
    final db = await _databaseService.database;

    await db.insert('movimentacoes_financeiras', {
      ...movimento.paraMapa(),
      'comercio_id': _comercioId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> atualizar(MovimentoFinanceiroRegistro movimento) async {
    final db = await _databaseService.database;

    await db.update(
      'movimentacoes_financeiras',
      movimento.paraMapa(),
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [movimento.id, _comercioId],
    );
  }

  Future<void> excluir(String id) async {
    final db = await _databaseService.database;

    await db.delete(
      'movimentacoes_financeiras',
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [id, _comercioId],
    );
  }

  Future<MovimentoFinanceiroRegistro?> buscarPorId(String id) async {
    final db = await _databaseService.database;

    final resultado = await db.query(
      'movimentacoes_financeiras',
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [id, _comercioId],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    return MovimentoFinanceiroRegistro.doMapa(resultado.first);
  }

  Future<ResumoCaixa> resumoDoPeriodo({
    required DateTime inicio,
    required DateTime fim,
  }) async {
    final lista = await listarPorPeriodo(inicio: inicio, fim: fim);

    double entradas = 0;
    double saidas = 0;

    int qtdEntradas = 0;
    int qtdSaidas = 0;

    for (final item in lista) {
      if (item.entrada) {
        entradas += item.valor;
        qtdEntradas++;
      } else {
        saidas += item.valor;
        qtdSaidas++;
      }
    }

    return ResumoCaixa(
      totalEntradas: entradas,
      totalSaidas: saidas,
      saldo: entradas - saidas,
      quantidadeEntradas: qtdEntradas,
      quantidadeSaidas: qtdSaidas,
    );
  }

  Future<void> registrarEntradaServico({
    required String descricao,
    required double valor,
    required String clienteId,
    required String profissionalId,
    required String agendamentoId,
    required String servicoId,
    String formaPagamento = 'Dinheiro',
  }) async {
    final agora = DateTime.now();

    await inserir(
      MovimentoFinanceiroRegistro(
        id: agora.microsecondsSinceEpoch.toString(),
        tipo: 'entrada',
        descricao: descricao,
        valor: valor,
        formaPagamento: formaPagamento,
        status: 'pago',
        data: agora,
        dataCriacao: agora,
        categoria: 'Serviços',
        clienteId: clienteId,
        profissionalId: profissionalId,
        agendamentoId: agendamentoId,
        servicoId: servicoId,
        usuarioResponsavelId: null,
        observacoes: '',
        centroResultado: 'salao',
        entidadeOrigem: 'agendamento',
        entidadeOrigemId: agendamentoId,
      ),
    );
  }

  Future<void> registrarSaida({
    required String descricao,
    required double valor,
    required String categoria,
    required String formaPagamento,
    String observacoes = '',
  }) async {
    final agora = DateTime.now();

    await inserir(
      MovimentoFinanceiroRegistro(
        id: agora.microsecondsSinceEpoch.toString(),
        tipo: 'saida',
        descricao: descricao,
        valor: valor,
        formaPagamento: formaPagamento,
        status: 'pago',
        data: agora,
        dataCriacao: agora,
        categoria: categoria,
        clienteId: null,
        profissionalId: null,
        agendamentoId: null,
        servicoId: null,
        usuarioResponsavelId: null,
        observacoes: observacoes,
      ),
    );
  }

  Future<bool> existeEntradaDoAgendamento(String agendamentoId) async {
    final Database db = await _databaseService.database;

    final resultado = await db.query(
      'movimentacoes_financeiras',
      columns: ['id'],
      where: 'agendamento_id = ? AND tipo = ? AND comercio_id = ?',
      whereArgs: [agendamentoId, 'entrada', _comercioId],
      limit: 1,
    );

    return resultado.isNotEmpty;
  }

  Future<void> registrarEntradaDeAgendamento({
    required String descricao,
    required double valor,
    required String clienteId,
    required String profissionalId,
    required String agendamentoId,
    required String servicoId,
    required String formaPagamento,
  }) async {
    final jaExiste = await existeEntradaDoAgendamento(agendamentoId);

    if (jaExiste) {
      return;
    }

    await registrarEntradaServico(
      descricao: descricao,
      valor: valor,
      clienteId: clienteId,
      profissionalId: profissionalId,
      agendamentoId: agendamentoId,
      servicoId: servicoId,
      formaPagamento: formaPagamento,
    );
  }

  Future<ResumoCaixa> resumoDoDia(DateTime data) async {
    final inicio = DateTime(data.year, data.month, data.day);

    final fim = inicio.add(const Duration(days: 1));

    return resumoDoPeriodo(inicio: inicio, fim: fim);
  }

  Future<ResumoCaixa> resumoDaSemana(DateTime data) async {
    final diaSemHora = DateTime(data.year, data.month, data.day);

    final inicio = diaSemHora.subtract(Duration(days: diaSemHora.weekday - 1));

    final fim = inicio.add(const Duration(days: 7));

    return resumoDoPeriodo(inicio: inicio, fim: fim);
  }

  Future<ResumoCaixa> resumoDoMes(DateTime data) async {
    final inicio = DateTime(data.year, data.month, 1);

    final fim = data.month == 12
        ? DateTime(data.year + 1, 1, 1)
        : DateTime(data.year, data.month + 1, 1);

    return resumoDoPeriodo(inicio: inicio, fim: fim);
  }

  Future<double> totalPorProfissional({
    required String profissionalId,
    required DateTime inicio,
    required DateTime fim,
  }) async {
    final Database db = await _databaseService.database;

    final resultado = await db.rawQuery(
      '''
      SELECT SUM(valor) AS total
      FROM movimentacoes_financeiras
      WHERE profissional_id = ?
        AND tipo = ?
        AND status = ?
        AND data >= ?
        AND data < ?
        AND comercio_id = ?
      ''',
      [
        profissionalId,
        'entrada',
        'pago',
        inicio.toIso8601String(),
        fim.toIso8601String(),
        _comercioId,
      ],
    );

    final valor = resultado.first['total'];

    if (valor == null) {
      return 0;
    }

    return (valor as num).toDouble();
  }

  Future<double> calcularComissao({
    required String profissionalId,
    required DateTime inicio,
    required DateTime fim,
    required double percentual,
  }) async {
    final total = await totalPorProfissional(
      profissionalId: profissionalId,
      inicio: inicio,
      fim: fim,
    );

    return total * percentual / 100;
  }

  Future<List<MovimentoFinanceiroRegistro>> listarEntradasPorProfissional({
    required String profissionalId,
    required DateTime inicio,
    required DateTime fim,
  }) async {
    final Database db = await _databaseService.database;

    final registros = await db.query(
      'movimentacoes_financeiras',
      where: '''
        profissional_id = ?
        AND tipo = ?
        AND data >= ?
        AND data < ?
        AND comercio_id = ?
      ''',
      whereArgs: [
        profissionalId,
        'entrada',
        inicio.toIso8601String(),
        fim.toIso8601String(),
      ],
      orderBy: 'data DESC',
    );

    return registros.map(MovimentoFinanceiroRegistro.doMapa).toList();
  }
}
