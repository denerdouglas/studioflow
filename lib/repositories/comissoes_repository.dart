import 'package:sqflite/sqflite.dart';

import '../database/database_service.dart';
import '../services/session_controller.dart';

class ComissaoRegistro {
  final String id;
  final String profissionalId;
  final String agendamentoId;
  final String servicoId;

  final double valorServico;
  final double percentualComissao;
  final double valorComissao;

  final DateTime dataGeracao;
  final DateTime? dataPagamento;

  final String status;
  final String observacoes;

  const ComissaoRegistro({
    required this.id,
    required this.profissionalId,
    required this.agendamentoId,
    required this.servicoId,
    required this.valorServico,
    required this.percentualComissao,
    required this.valorComissao,
    required this.dataGeracao,
    required this.dataPagamento,
    required this.status,
    required this.observacoes,
  });

  Map<String, Object?> paraMapa() {
    return {
      'id': id,
      'profissional_id': profissionalId,
      'agendamento_id': agendamentoId,
      'servico_id': servicoId,
      'valor_servico': valorServico,
      'percentual_comissao': percentualComissao,
      'valor_comissao': valorComissao,
      'data_geracao': dataGeracao.toIso8601String(),
      'data_pagamento': dataPagamento?.toIso8601String(),
      'status': status,
      'observacoes': observacoes,
    };
  }

  factory ComissaoRegistro.doMapa(Map<String, Object?> mapa) {
    return ComissaoRegistro(
      id: mapa['id'] as String,
      profissionalId: mapa['profissional_id'] as String,
      agendamentoId: mapa['agendamento_id'] as String,
      servicoId: mapa['servico_id'] as String,
      valorServico: (mapa['valor_servico'] as num).toDouble(),
      percentualComissao: (mapa['percentual_comissao'] as num).toDouble(),
      valorComissao: (mapa['valor_comissao'] as num).toDouble(),
      dataGeracao: DateTime.parse(mapa['data_geracao'] as String),
      dataPagamento: mapa['data_pagamento'] == null
          ? null
          : DateTime.parse(mapa['data_pagamento'] as String),
      status: mapa['status'] as String? ?? 'pendente',
      observacoes: mapa['observacoes'] as String? ?? '',
    );
  }
}

class ComissoesRepository {
  final DatabaseService database = DatabaseService.instance;

  Future<Database> get _db async => database.database;
  String get _comercioId => SessionController.instance.usuario!.comercioId;
  Future<List<ComissaoRegistro>> listar({
    String? profissionalId,
    String? status,
  }) async {
    final db = await _db;

    String where = 'comercio_id = ?';
    final argumentos = <Object?>[_comercioId];

    if (profissionalId != null) {
      where += ' AND profissional_id = ?';
      argumentos.add(profissionalId);
    }

    if (status != null) {
      where += ' AND status = ?';

      argumentos.add(status);
    }

    final resultado = await db.query(
      'comissoes',
      where: where,
      whereArgs: argumentos,
      orderBy: 'data_geracao DESC',
    );

    return resultado.map(ComissaoRegistro.doMapa).toList();
  }

  Future<ComissaoRegistro?> buscarPorId(String id) async {
    final db = await _db;

    final resultado = await db.query(
      'comissoes',
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [id, _comercioId],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    return ComissaoRegistro.doMapa(resultado.first);
  }

  Future<void> inserir(ComissaoRegistro registro) async {
    final db = await _db;

    await db.insert('comissoes', {
      ...registro.paraMapa(),
      'comercio_id': _comercioId,
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<void> atualizar(ComissaoRegistro registro) async {
    final db = await _db;

    await db.update(
      'comissoes',
      registro.paraMapa(),
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [registro.id, _comercioId],
    );
  }

  Future<void> salvar(ComissaoRegistro registro) async {
    final existente = await buscarPorId(registro.id);

    if (existente == null) {
      await inserir(registro);
      return;
    }

    await atualizar(registro);
  }

  Future<void> excluir(String id) async {
    final db = await _db;

    await db.delete(
      'comissoes',
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [id, _comercioId],
    );
  }

  Future<void> marcarComoPaga(String id) async {
    final db = await _db;

    await db.update(
      'comissoes',
      {'status': 'pago', 'data_pagamento': DateTime.now().toIso8601String()},
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [id, _comercioId],
    );
  }

  Future<void> marcarComoPendente(String id) async {
    final db = await _db;

    await db.update(
      'comissoes',
      {'status': 'pendente', 'data_pagamento': null},
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [id, _comercioId],
    );
  }

  Future<double> totalPendente() async {
    final db = await _db;

    final resultado = await db.rawQuery(
      '''
      SELECT SUM(valor_comissao) AS total
      FROM comissoes
      WHERE status = 'pendente' AND comercio_id = ?
      ''',
      [_comercioId],
    );

    return (resultado.first['total'] as num? ?? 0).toDouble();
  }

  Future<double> totalPago() async {
    final db = await _db;

    final resultado = await db.rawQuery(
      '''
      SELECT SUM(valor_comissao) AS total
      FROM comissoes
      WHERE status = 'pago' AND comercio_id = ?
      ''',
      [_comercioId],
    );

    return (resultado.first['total'] as num? ?? 0).toDouble();
  }

  Future<int> quantidade() async {
    final db = await _db;

    final resultado = await db.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM comissoes WHERE comercio_id = ?
      ''',
      [_comercioId],
    );

    return (resultado.first['total'] as num? ?? 0).toInt();
  }

  Future<void> limparTudo() async {
    final db = await _db;

    await db.delete(
      'comissoes',
      where: 'comercio_id = ?',
      whereArgs: [_comercioId],
    );
  }
}
