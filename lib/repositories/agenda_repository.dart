import 'package:sqflite/sqflite.dart';

import '../database/database_service.dart';
import '../models/domain/acesso.dart';
import '../services/session_controller.dart';
import '../services/whatsapp_queue_service.dart';
import 'pacotes_repository.dart';

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

  final String observacoes;

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
    required this.observacoes,
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
      'observacoes': observacoes,
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

      observacoes: mapa['observacoes'] as String? ?? '',

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
    String? status,
    bool? confirmado,
    bool? compareceu,
    bool? encaixe,
    double? valorRecebido,
    String? observacoes,
  }) {
    return AgendamentoRegistro(
      id: id,
      clienteId: clienteId,
      clienteNome: clienteNome,
      profissionalId: profissionalId,
      profissionalNome: profissionalNome,
      servicoId: servicoId,
      servicoNome: servicoNome,
      inicio: inicio,
      fim: fim,
      status: status ?? this.status,
      valorServico: valorServico,
      desconto: desconto,
      valorRecebido: valorRecebido ?? this.valorRecebido,
      confirmado: confirmado ?? this.confirmado,
      compareceu: compareceu ?? this.compareceu,
      encaixe: encaixe ?? this.encaixe,
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

  Future<void> inserir(AgendamentoRegistro agendamento) async {
    final Database db = await _databaseService.database;

    final possuiConflito = await verificarConflito(
      profissionalId: agendamento.profissionalId,
      inicio: agendamento.inicio,
      fim: agendamento.fim,
    );

    if (possuiConflito) {
      throw StateError(
        'Já existe um agendamento nesse horário para essa profissional.',
      );
    }

    await db.transaction((txn) async {
      await txn.insert('agendamentos', {
        ...agendamento.paraMapa(),
        'comercio_id': _comercioId,
      }, conflictAlgorithm: ConflictAlgorithm.abort);

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
    });
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
      throw StateError('Já existe outro agendamento nesse horário.');
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

  Future<void> concluirAgendamento({
    required String agendamentoId,
    required double valorRecebido,
  }) async {
    final Database db = await _databaseService.database;

    final pacote = await db.query(
      'agendamentos',
      columns: ['pacote_venda_sessao_id'],
      where: 'id = ? AND comercio_id = ? AND excluido = 0',
      whereArgs: [agendamentoId, _comercioId],
      limit: 1,
    );
    if (pacote.isNotEmpty && pacote.first['pacote_venda_sessao_id'] != null) {
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
