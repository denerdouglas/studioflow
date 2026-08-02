import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../database/database_service.dart';
import '../models/domain/acesso.dart';
import '../models/domain/atendimento.dart';
import '../services/session_controller.dart';
import '../services/whatsapp_queue_service.dart';
import 'pacotes_repository.dart';

class DiagnosticoExclusaoAgendamento {
  final int financeiros;
  final int comissoes;
  final int cobrancasPagas;
  final int sessoesPacote;
  final double valorRecebido;
  final String status;

  const DiagnosticoExclusaoAgendamento({
    required this.financeiros,
    required this.comissoes,
    required this.cobrancasPagas,
    required this.sessoesPacote,
    required this.valorRecebido,
    required this.status,
  });

  bool get bloqueado =>
      financeiros > 0 ||
      comissoes > 0 ||
      cobrancasPagas > 0 ||
      sessoesPacote > 0 ||
      valorRecebido > 0 ||
      status == 'concluido';

  Map<String, Object?> toJson() => {
    'movimentacoes_financeiras': financeiros,
    'comissoes': comissoes,
    'cobrancas_pagas': cobrancasPagas,
    'sessoes_pacote': sessoesPacote,
    'valor_recebido': valorRecebido,
    'status': status,
  };
}

class AgendaCompletaRepository {
  final Future<Database> Function() _databaseProvider;
  final String? _comercioInformado;
  final String? _usuarioInformado;

  AgendaCompletaRepository({
    Future<Database> Function()? databaseProvider,
    String? comercioId,
    String? usuarioId,
  }) : _databaseProvider =
           databaseProvider ?? (() => DatabaseService.instance.database),
       _comercioInformado = comercioId,
       _usuarioInformado = usuarioId;

  String get _comercioId =>
      _comercioInformado ?? SessionController.instance.usuario!.comercioId;
  String get _usuarioId =>
      _usuarioInformado ?? SessionController.instance.usuario!.id;
  String _id(String prefixo) =>
      '${prefixo}_${_comercioId}_${DateTime.now().microsecondsSinceEpoch}';

  void _exigirGerencia() {
    final usuario = SessionController.instance.usuario;
    if (usuario == null || !usuario.podeAcao(AcaoPermissao.gerenciarAgenda)) {
      throw StateError('Você não possui permissão para gerenciar agenda.');
    }
  }

  Future<List<Map<String, Object?>>> listarProfissionais() async {
    final db = await _databaseProvider();
    return db.query(
      'profissionais',
      columns: ['id', 'nome'],
      where: 'comercio_id = ? AND ativo = 1',
      whereArgs: [_comercioId],
      orderBy: 'nome COLLATE NOCASE',
    );
  }

  Future<void> criarHorariosPadrao() async {
    _exigirGerencia();
    final db = await _databaseProvider();
    final profissionais = await listarProfissionais();
    final config = await db.query(
      'configuracoes',
      where: 'comercio_id = ?',
      whereArgs: [_comercioId],
    );
    final valores = <String, String>{};
    for (final row in config) {
      final chave = (row['chave'] as String).replaceFirst('$_comercioId.', '');
      valores[chave] = row['valor'] as String? ?? '';
    }
    final inicio = valores['horario_abertura'] ?? '08:00';
    final fim = valores['horario_fechamento'] ?? '18:00';
    final agora = DateTime.now().toUtc().toIso8601String();
    for (final profissional in profissionais) {
      for (var dia = 1; dia <= 6; dia++) {
        await db.insert('horarios_profissionais', {
          'id': _id('hor'),
          'comercio_id': _comercioId,
          'profissional_id': profissional['id'],
          'dia_semana': dia,
          'inicio': inicio,
          'fim': fim,
          'ativo': 1,
          'criado_em': agora,
          'atualizado_em': agora,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
  }

  Future<List<HorarioProfissional>> listarHorarios() async {
    final db = await _databaseProvider();
    final rows = await db.rawQuery(
      '''SELECT h.*, p.nome AS profissional_nome
         FROM horarios_profissionais h
         JOIN profissionais p ON p.id = h.profissional_id
         WHERE h.comercio_id = ?
         ORDER BY p.nome COLLATE NOCASE, h.dia_semana''',
      [_comercioId],
    );
    return rows
        .map(
          (e) => HorarioProfissional(
            id: e['id'] as String,
            profissionalId: e['profissional_id'] as String,
            profissionalNome: e['profissional_nome'] as String? ?? '',
            diaSemana: e['dia_semana'] as int,
            inicio: e['inicio'] as String,
            fim: e['fim'] as String,
            intervaloInicio: e['intervalo_inicio'] as String?,
            intervaloFim: e['intervalo_fim'] as String?,
            ativo: (e['ativo'] as int) == 1,
          ),
        )
        .toList();
  }

  Future<void> salvarHorario(HorarioProfissional horario) async {
    _exigirGerencia();
    if (_minutos(horario.fim) <= _minutos(horario.inicio)) {
      throw ArgumentError('O fim do expediente deve ser posterior ao início.');
    }
    final db = await _databaseProvider();
    final agora = DateTime.now().toUtc().toIso8601String();
    await db.insert('horarios_profissionais', {
      'id': horario.id.isEmpty ? _id('hor') : horario.id,
      'comercio_id': _comercioId,
      'profissional_id': horario.profissionalId,
      'dia_semana': horario.diaSemana,
      'inicio': horario.inicio,
      'fim': horario.fim,
      'intervalo_inicio': horario.intervaloInicio,
      'intervalo_fim': horario.intervaloFim,
      'ativo': horario.ativo ? 1 : 0,
      'criado_em': agora,
      'atualizado_em': agora,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<BloqueioAgenda>> listarBloqueios({DateTime? aPartirDe}) async {
    final db = await _databaseProvider();
    final inicio =
        (aPartirDe ?? DateTime.now().subtract(const Duration(days: 1)))
            .toIso8601String();
    final rows = await db.rawQuery(
      '''SELECT b.*, p.nome AS profissional_nome
         FROM bloqueios_agenda b
         LEFT JOIN profissionais p ON p.id = b.profissional_id
         WHERE b.comercio_id = ? AND b.fim >= ? ORDER BY b.inicio''',
      [_comercioId, inicio],
    );
    return rows
        .map(
          (e) => BloqueioAgenda(
            id: e['id'] as String,
            profissionalId: e['profissional_id'] as String?,
            profissionalNome:
                e['profissional_nome'] as String? ?? 'Toda a equipe',
            inicio: DateTime.parse(e['inicio'] as String),
            fim: DateTime.parse(e['fim'] as String),
            tipo: e['tipo'] as String,
            motivo: e['motivo'] as String? ?? '',
          ),
        )
        .toList();
  }

  Future<void> adicionarBloqueio(BloqueioAgenda bloqueio) async {
    _exigirGerencia();
    if (!bloqueio.fim.isAfter(bloqueio.inicio)) {
      throw ArgumentError('O fim do bloqueio deve ser posterior ao início.');
    }
    final db = await _databaseProvider();
    await db.insert('bloqueios_agenda', {
      'id': bloqueio.id.isEmpty ? _id('bloq') : bloqueio.id,
      'comercio_id': _comercioId,
      'profissional_id': bloqueio.profissionalId,
      'inicio': bloqueio.inicio.toIso8601String(),
      'fim': bloqueio.fim.toIso8601String(),
      'tipo': bloqueio.tipo,
      'motivo': bloqueio.motivo,
      'criado_por_id': _usuarioId,
      'criado_em': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> removerBloqueio(String id) async {
    _exigirGerencia();
    final db = await _databaseProvider();
    await db.delete(
      'bloqueios_agenda',
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [id, _comercioId],
    );
  }

  Future<List<DateTime>> horariosDisponiveis({
    required String profissionalId,
    required DateTime data,
    required int duracaoMinutos,
    int intervaloMinutos = 15,
  }) async {
    final db = await _databaseProvider();
    final horarios = await db.query(
      'horarios_profissionais',
      where:
          'comercio_id = ? AND profissional_id = ? AND dia_semana = ? AND ativo = 1',
      whereArgs: [_comercioId, profissionalId, data.weekday],
      limit: 1,
    );
    if (horarios.isEmpty) return [];
    final h = horarios.first;
    final expedienteInicio = _emData(data, h['inicio'] as String);
    final expedienteFim = _emData(data, h['fim'] as String);
    final intervaloInicio = h['intervalo_inicio'] == null
        ? null
        : _emData(data, h['intervalo_inicio'] as String);
    final intervaloFim = h['intervalo_fim'] == null
        ? null
        : _emData(data, h['intervalo_fim'] as String);
    final diaFim = DateTime(
      data.year,
      data.month,
      data.day,
    ).add(const Duration(days: 1));
    final agendamentos = await db.query(
      'agendamentos',
      columns: ['inicio', 'fim'],
      where:
          "comercio_id = ? AND profissional_id = ? AND status != 'cancelado' AND excluido = 0 AND inicio < ? AND fim > ?",
      whereArgs: [
        _comercioId,
        profissionalId,
        diaFim.toIso8601String(),
        DateTime(data.year, data.month, data.day).toIso8601String(),
      ],
    );
    final bloqueios = await db.query(
      'bloqueios_agenda',
      columns: ['inicio', 'fim'],
      where:
          'comercio_id = ? AND (profissional_id IS NULL OR profissional_id = ?) AND inicio < ? AND fim > ?',
      whereArgs: [
        _comercioId,
        profissionalId,
        diaFim.toIso8601String(),
        DateTime(data.year, data.month, data.day).toIso8601String(),
      ],
    );
    final ocupados = [...agendamentos, ...bloqueios];
    final livres = <DateTime>[];
    for (
      var atual = expedienteInicio;
      !atual.add(Duration(minutes: duracaoMinutos)).isAfter(expedienteFim);
      atual = atual.add(Duration(minutes: intervaloMinutos))
    ) {
      final fim = atual.add(Duration(minutes: duracaoMinutos));
      final noIntervalo =
          intervaloInicio != null &&
          intervaloFim != null &&
          atual.isBefore(intervaloFim) &&
          fim.isAfter(intervaloInicio);
      final ocupado = ocupados.any((item) {
        final ini = DateTime.parse(item['inicio'] as String);
        final end = DateTime.parse(item['fim'] as String);
        return atual.isBefore(end) && fim.isAfter(ini);
      });
      if (!noIntervalo && !ocupado) livres.add(atual);
    }
    return livres;
  }

  Future<void> reagendar({
    required String agendamentoId,
    required DateTime novoInicio,
    required DateTime novoFim,
    String motivo = '',
  }) async {
    _exigirGerencia();
    final db = await _databaseProvider();
    await db.transaction((txn) async {
      final rows = await txn.query(
        'agendamentos',
        where: 'id = ? AND comercio_id = ?',
        whereArgs: [agendamentoId, _comercioId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Agendamento não encontrado.');
      final atual = rows.first;
      final conflitos = await txn.query(
        'agendamentos',
        columns: ['id'],
        where:
            "comercio_id = ? AND profissional_id = ? AND id != ? AND status != 'cancelado' AND excluido = 0 AND inicio < ? AND fim > ?",
        whereArgs: [
          _comercioId,
          atual['profissional_id'],
          agendamentoId,
          novoFim.toIso8601String(),
          novoInicio.toIso8601String(),
        ],
        limit: 1,
      );
      if (conflitos.isNotEmpty) {
        throw StateError('O novo horário está ocupado.');
      }
      await txn.update(
        'agendamentos',
        {
          'inicio': novoInicio.toIso8601String(),
          'fim': novoFim.toIso8601String(),
          'status': 'agendado',
          'confirmado': 0,
          'atualizado_em': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ? AND comercio_id = ?',
        whereArgs: [agendamentoId, _comercioId],
      );
      await _historico(
        txn,
        agendamentoId: agendamentoId,
        acao: 'reagendamento',
        statusAnterior: atual['status'] as String?,
        statusNovo: 'agendado',
        detalhes:
            '${atual['inicio']} → ${novoInicio.toIso8601String()}${motivo.isEmpty ? '' : ' • $motivo'}',
      );
    });
  }

  void _exigirExclusao() {
    final usuario = SessionController.instance.usuario;
    if (usuario == null ||
        !usuario.podeAcao(AcaoPermissao.excluirAgendamento)) {
      throw StateError('Você não possui permissão para excluir agendamentos.');
    }
  }

  Future<DiagnosticoExclusaoAgendamento> diagnosticarExclusao(
    String agendamentoId,
  ) async {
    final db = await _databaseProvider();
    return _diagnosticar(db, agendamentoId);
  }

  Future<void> excluirSeguro({
    required String agendamentoId,
    required String motivo,
  }) async {
    _exigirExclusao();
    if (motivo.trim().length < 5) {
      throw StateError(
        'Informe um motivo de exclusão com pelo menos 5 caracteres.',
      );
    }
    final db = await _databaseProvider();
    await db.transaction((txn) async {
      final rows = await txn.query(
        'agendamentos',
        where: 'id = ? AND comercio_id = ? AND excluido = 0',
        whereArgs: [agendamentoId, _comercioId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Agendamento não encontrado.');
      final diagnostico = await _diagnosticar(txn, agendamentoId);
      if (diagnostico.bloqueado) {
        throw StateError(
          'Exclusão bloqueada: existem vínculos financeiros, pacote ou atendimento concluído. Cancele o agendamento e faça os estornos necessários.',
        );
      }
      final agora = DateTime.now().toUtc().toIso8601String();
      final notificacoes = await txn.update(
        'notificacoes',
        {'status': 'cancelada'},
        where: "comercio_id = ? AND referencia_id = ? AND status = 'pendente'",
        whereArgs: [_comercioId, agendamentoId],
      );
      final whatsapp = await txn.update(
        'whatsapp_fila',
        {'status': 'cancelado', 'atualizado_em': agora},
        where:
            "comercio_id = ? AND (agendamento_id = ? OR payload_json LIKE ?) AND status NOT IN ('enviado','entregue','lido','cancelado')",
        whereArgs: [_comercioId, agendamentoId, '%$agendamentoId%'],
      );
      await txn.update(
        'cobrancas',
        {'status': 'cancelado'},
        where: "comercio_id = ? AND agendamento_id = ? AND status = 'pendente'",
        whereArgs: [_comercioId, agendamentoId],
      );
      await txn.update(
        'agendamentos',
        {
          'status': 'cancelado',
          'cancelamento_motivo': motivo.trim(),
          'excluido': 1,
          'excluido_em': agora,
          'excluido_por_id': _usuarioId,
          'exclusao_motivo': motivo.trim(),
          'atualizado_em': agora,
        },
        where: 'id = ? AND comercio_id = ?',
        whereArgs: [agendamentoId, _comercioId],
      );
      await txn.insert('agendamento_exclusoes', {
        'id': _id('exc'),
        'comercio_id': _comercioId,
        'agendamento_id': agendamentoId,
        'usuario_id': _usuarioId,
        'motivo': motivo.trim(),
        'snapshot_json': jsonEncode(rows.first),
        'vinculos_json': jsonEncode(diagnostico.toJson()),
        'mensagens_canceladas': notificacoes + whatsapp,
        'excluido_em': agora,
      });

      final cliente = await txn.query(
        'clientes',
        columns: ['whatsapp'],
        where: 'id = ? AND comercio_id = ?',
        whereArgs: [rows.first['cliente_id'], _comercioId],
      );
      if (cliente.isNotEmpty) {
        final whatsapp = cliente.first['whatsapp'] as String?;
        if (whatsapp != null && whatsapp.isNotEmpty) {
          await WhatsappQueueService().enfileirar(
            txn: txn,
            comercioId: _comercioId,
            destinatario: whatsapp,
            template: 'agendamento_cancelado',
            payload: {'motivo': motivo.trim(), ...rows.first},
            agendamentoId: agendamentoId,
          );
        }
      }

      await _historico(
        txn,
        agendamentoId: agendamentoId,
        acao: 'exclusao_logica',
        statusAnterior: rows.first['status'] as String?,
        statusNovo: 'cancelado',
        detalhes: motivo.trim(),
      );
    });
  }

  Future<DiagnosticoExclusaoAgendamento> _diagnosticar(
    DatabaseExecutor db,
    String agendamentoId,
  ) async {
    Future<int> contar(
      String tabela, {
      String extra = '',
      List<Object?> adicionais = const [],
    }) async {
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS total FROM $tabela WHERE comercio_id = ? AND agendamento_id = ? $extra',
        [_comercioId, agendamentoId, ...adicionais],
      );
      return (rows.first['total'] as num? ?? 0).toInt();
    }

    final agenda = await db.query(
      'agendamentos',
      columns: ['status', 'valor_recebido'],
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [agendamentoId, _comercioId],
      limit: 1,
    );
    if (agenda.isEmpty) throw StateError('Agendamento não encontrado.');
    return DiagnosticoExclusaoAgendamento(
      financeiros: await contar('movimentacoes_financeiras'),
      comissoes: await contar('comissoes'),
      cobrancasPagas: await contar(
        'cobrancas',
        extra: "AND status IN ('pago','confirmado')",
      ),
      sessoesPacote: await contar('pacote_venda_sessoes'),
      valorRecebido: (agenda.first['valor_recebido'] as num? ?? 0).toDouble(),
      status: agenda.first['status'] as String? ?? '',
    );
  }

  Future<void> registrarStatus({
    required String agendamentoId,
    required String status,
    String detalhes = '',
  }) async {
    _exigirGerencia();
    if (status == 'cancelado' && detalhes.trim().length < 3) {
      throw StateError('Informe o motivo do cancelamento.');
    }
    final db = await _databaseProvider();
    final pacote = await db.query(
      'agendamentos',
      columns: ['pacote_venda_sessao_id'],
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [agendamentoId, _comercioId],
      limit: 1,
    );
    final ehPacote =
        pacote.isNotEmpty && pacote.first['pacote_venda_sessao_id'] != null;
    final pacotes = PacotesRepository(
      databaseProvider: _databaseProvider,
      comercioId: _comercioId,
      usuarioId: _usuarioId,
    );
    if (ehPacote && status == 'faltou') {
      await pacotes.registrarFalta(agendamentoId);
      return;
    }
    if (ehPacote && status == 'cancelado') {
      await pacotes.cancelarAgendamentoPacote(agendamentoId);
    }
    await db.transaction((txn) async {
      final rows = await txn.query(
        'agendamentos',
        columns: ['status'],
        where: 'id = ? AND comercio_id = ?',
        whereArgs: [agendamentoId, _comercioId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Agendamento não encontrado.');
      final anterior = rows.first['status'] as String;
      final dados = <String, Object?>{
        'status': status,
        'confirmado': status == 'confirmado' ? 1 : 0,
        'compareceu': status == 'concluido' ? 1 : 0,
        'atualizado_em': DateTime.now().toUtc().toIso8601String(),
      };
      if (status == 'cancelado') dados['cancelamento_motivo'] = detalhes;
      await txn.update(
        'agendamentos',
        dados,
        where: 'id = ? AND comercio_id = ?',
        whereArgs: [agendamentoId, _comercioId],
      );
      if (status == 'cancelado') {
        final agora = DateTime.now().toUtc().toIso8601String();
        await txn.update(
          'notificacoes',
          {'status': 'cancelada'},
          where:
              "comercio_id = ? AND referencia_id = ? AND status = 'pendente'",
          whereArgs: [_comercioId, agendamentoId],
        );
        await txn.update(
          'whatsapp_fila',
          {'status': 'cancelado', 'atualizado_em': agora},
          where:
              "comercio_id = ? AND (agendamento_id = ? OR payload_json LIKE ?) AND status NOT IN ('enviado','entregue','lido','cancelado')",
          whereArgs: [_comercioId, agendamentoId, '%$agendamentoId%'],
        );
      }

      await _historico(
        txn,
        agendamentoId: agendamentoId,
        acao: status,
        statusAnterior: anterior,
        statusNovo: status,
        detalhes: detalhes,
      );
    });
  }

  Future<List<EventoAgendamento>> listarHistorico(String agendamentoId) async {
    final db = await _databaseProvider();
    final rows = await db.query(
      'agendamento_historico',
      where: 'comercio_id = ? AND agendamento_id = ?',
      whereArgs: [_comercioId, agendamentoId],
      orderBy: 'data DESC',
    );
    return rows
        .map(
          (e) => EventoAgendamento(
            acao: e['acao'] as String,
            statusAnterior: e['status_anterior'] as String?,
            statusNovo: e['status_novo'] as String?,
            detalhes: e['detalhes'] as String? ?? '',
            data: DateTime.parse(e['data'] as String),
            usuarioId: e['usuario_id'] as String,
          ),
        )
        .toList();
  }

  Future<String> criarRascunhoLinkPublico({
    String? servicoId,
    String? profissionalId,
    required String politicaCancelamento,
    required bool exigeSinal,
  }) async {
    final db = await _databaseProvider();
    final token =
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_comercioId.hashCode.abs().toRadixString(36)}';
    await db.insert('links_agendamento', {
      'id': _id('link'),
      'comercio_id': _comercioId,
      'token': token,
      'servico_id': servicoId,
      'profissional_id': profissionalId,
      'politica_cancelamento': politicaCancelamento,
      'exige_sinal': exigeSinal ? 1 : 0,
      'status': 'rascunho',
      'criado_em': DateTime.now().toUtc().toIso8601String(),
    });
    return token;
  }

  Future<void> _historico(
    DatabaseExecutor db, {
    required String agendamentoId,
    required String acao,
    String? statusAnterior,
    String? statusNovo,
    String detalhes = '',
  }) => db.insert('agendamento_historico', {
    'id': _id('hist'),
    'comercio_id': _comercioId,
    'agendamento_id': agendamentoId,
    'usuario_id': _usuarioId,
    'acao': acao,
    'status_anterior': statusAnterior,
    'status_novo': statusNovo,
    'detalhes': detalhes,
    'data': DateTime.now().toUtc().toIso8601String(),
  });

  static int _minutos(String horario) {
    final partes = horario.split(':');
    if (partes.length != 2) throw const FormatException('Horário inválido.');
    return int.parse(partes[0]) * 60 + int.parse(partes[1]);
  }

  static DateTime _emData(DateTime data, String horario) {
    final minutos = _minutos(horario);
    return DateTime(
      data.year,
      data.month,
      data.day,
      minutos ~/ 60,
      minutos % 60,
    );
  }
}
