import 'package:sqflite/sqflite.dart';

import '../core/utils/id_generator.dart';
import '../database/database_service.dart';
import '../services/session_controller.dart';

enum ConsignacaoResolveState {
  encontrada,
  jaConferida,
  outraRemessa,
  statusInvalido,
  naoEncontrada,
  multiplas
}

class ConsignacaoResolveResult {
  final ConsignacaoResolveState state;
  final Map<String, Object?>? peca;
  final List<Map<String, Object?>> multiplasOpcoes;

  const ConsignacaoResolveResult({
    required this.state,
    this.peca,
    this.multiplasOpcoes = const [],
  });
}
class ConsignacaoConferenciaRepository {
  final Future<Database> Function() _databaseProvider;
  final String? _commerceOverride;
  final String? _userOverride;

  ConsignacaoConferenciaRepository({
    Future<Database> Function()? databaseProvider,
    String? comercioId,
    String? usuarioId,
  }) : _databaseProvider =
           databaseProvider ?? (() => DatabaseService.instance.database),
       _commerceOverride = comercioId,
       _userOverride = usuarioId;

  String get _commerce =>
      _commerceOverride ?? SessionController.instance.usuario!.comercioId;
  String get _user => _userOverride ?? SessionController.instance.usuario!.id;

  Future<String> iniciar({
    required String remessaId,
    required String finalidade,
    String observacao = '',
  }) async {
    if (!const {
      'recebimento',
      'inventario',
      'devolucao',
    }.contains(finalidade)) {
      throw StateError('Finalidade de conferência inválida.');
    }
    final db = await _databaseProvider();
    final active = await db.query(
      'consignacao_conferencias',
      columns: ['id'],
      where:
          "comercio_id=? AND consignacao_id=? AND finalidade=? AND status IN ('em_andamento','pausada')",
      whereArgs: [_commerce, remessaId, finalidade],
      limit: 1,
    );
    if (active.isNotEmpty) return active.single['id'] as String;
    final expected =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM pecas_unicas WHERE comercio_id=? AND lote_id=?',
            [_commerce, remessaId],
          ),
        ) ??
        0;
    final id = IdGenerator.temporal();
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('consignacao_conferencias', {
      'id': id,
      'comercio_id': _commerce,
      'consignacao_id': remessaId,
      'finalidade': finalidade,
      'status': 'em_andamento',
      'esperado': expected,
      'conferido': 0,
      'pendente': expected,
      'iniciado_em': now,
      'responsavel_id': _user,
      'observacao': observacao.trim(),
      'criado_em': now,
      'atualizado_em': now,
    });
    return id;
  }

  Future<Map<String, Object?>> carregar(String id) async {
    final db = await _databaseProvider();
    final rows = await db.query(
      'consignacao_conferencias',
      where: 'id=? AND comercio_id=?',
      whereArgs: [id, _commerce],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Conferência não encontrada.');
    return rows.single;
  }

  Future<ConsignacaoResolveResult> resolverCodigo(
    String conferenciaId,
    String codigo,
  ) async {
    final db = await _databaseProvider();

    final confRows = await db.query(
      'consignacao_conferencias',
      columns: ['consignacao_id'],
      where: 'id=? AND comercio_id=?',
      whereArgs: [conferenciaId, _commerce],
      limit: 1,
    );
    if (confRows.isEmpty) throw StateError('Conferência não encontrada.');
    final loteId = confRows.first['consignacao_id'] as String;

    final pecas = await db.rawQuery(
      '''SELECT p.* FROM pecas_unicas p
      WHERE p.comercio_id=? AND p.codigo_exclusivo=?
      ORDER BY p.id''',
      [_commerce, codigo.trim()],
    );

    if (pecas.isEmpty) {
      return const ConsignacaoResolveResult(state: ConsignacaoResolveState.naoEncontrada);
    }

    final matchLote = pecas.where((p) => p['lote_id'] == loteId).toList();

    if (matchLote.isEmpty) {
      return ConsignacaoResolveResult(
        state: ConsignacaoResolveState.outraRemessa,
        peca: pecas.first,
      );
    }

    final conferredIdsResult = await db.query(
      'consignacao_conferencia_itens',
      columns: ['peca_unica_id'],
      where: 'conferencia_id=?',
      whereArgs: [conferenciaId],
    );
    final conferredIds = conferredIdsResult.map((e) => e['peca_unica_id'] as String).toSet();

    final matchLoteNaoConferidas = matchLote.where((p) => !conferredIds.contains(p['id'])).toList();

    if (matchLoteNaoConferidas.isEmpty) {
      return ConsignacaoResolveResult(
        state: ConsignacaoResolveState.jaConferida,
        peca: matchLote.first,
      );
    }

    final available = matchLoteNaoConferidas.where((p) => p['status'] == 'disponivel').toList();
    if (available.isEmpty) {
      return ConsignacaoResolveResult(
        state: ConsignacaoResolveState.statusInvalido,
        peca: matchLoteNaoConferidas.first,
      );
    }

    if (available.length > 1) {
      return ConsignacaoResolveResult(
        state: ConsignacaoResolveState.multiplas,
        multiplasOpcoes: available,
      );
    }

    return ConsignacaoResolveResult(
      state: ConsignacaoResolveState.encontrada,
      peca: available.single,
    );
  }

  Future<List<Map<String, Object?>>> pendentes(String conferenciaId) async {
    final db = await _databaseProvider();
    return db.rawQuery(
      '''SELECT p.* FROM pecas_unicas p
      JOIN consignacao_conferencias c ON c.consignacao_id=p.lote_id
      WHERE c.id=? AND c.comercio_id=? AND p.comercio_id=c.comercio_id
        AND NOT EXISTS (SELECT 1 FROM consignacao_conferencia_itens i
          WHERE i.conferencia_id=c.id AND i.peca_unica_id=p.id)
      ORDER BY p.codigo_exclusivo,p.id''',
      [conferenciaId, _commerce],
    );
  }

  Future<void> classificarPendente({
    required String conferenciaId,
    required String pecaId,
    required String resultado,
    String observacao = '',
  }) async {
    const allowed = {
      'vendida',
      'faltando',
      'perdida',
      'roubada',
      'avariada',
      'ainda_em_posse',
    };
    if (!allowed.contains(resultado)) {
      throw StateError('Classificação inválida.');
    }
    final db = await _databaseProvider();
    final pieces = await db.query(
      'pecas_unicas',
      columns: ['status', 'lote_id', 'preco'],
      where: 'id=? AND comercio_id=?',
      whereArgs: [pecaId, _commerce],
      limit: 1,
    );
    if (pieces.isEmpty) throw StateError('Peça não encontrada.');
    if (resultado == 'vendida' && pieces.single['status'] != 'vendida') {
      throw StateError('Venda precisa existir antes da classificação.');
    }
    await conferirPeca(
      conferenciaId: conferenciaId,
      pecaId: pecaId,
      leituraOriginal: 'classificacao_manual',
      resultado: resultado,
      observacao: observacao,
    );
    if (const {'perdida', 'roubada', 'avariada'}.contains(resultado)) {
      await db.transaction((tx) async {
        await tx.update(
          'pecas_unicas',
          {'status': resultado},
          where: 'id=? AND comercio_id=?',
          whereArgs: [pecaId, _commerce],
        );
        await tx.insert('consignacao_eventos', {
          'id': IdGenerator.temporal(),
          'comercio_id': _commerce,
          'consignacao_id': pieces.single['lote_id'],
          'peca_id': pecaId,
          'tipo': resultado,
          'quantidade': 1,
          'valor': pieces.single['preco'],
          'observacoes': observacao,
          'criado_em': DateTime.now().toUtc().toIso8601String(),
        });
      });
    }
  }

  Future<bool> conferirPeca({
    required String conferenciaId,
    required String pecaId,
    required String leituraOriginal,
    String resultado = 'conferida',
    String observacao = '',
  }) async {
    final db = await _databaseProvider();
    return db.transaction((tx) async {
      final conferences = await tx.query(
        'consignacao_conferencias',
        where:
            "id=? AND comercio_id=? AND status IN ('em_andamento','pausada')",
        whereArgs: [conferenciaId, _commerce],
        limit: 1,
      );
      if (conferences.isEmpty) {
        throw StateError('Conferência não está aberta.');
      }
      final conference = conferences.single;
      final pieces = await tx.query(
        'pecas_unicas',
        where: 'id=? AND lote_id=? AND comercio_id=?',
        whereArgs: [pecaId, conference['consignacao_id'], _commerce],
        limit: 1,
      );
      if (pieces.isEmpty) throw StateError('Peça não pertence à remessa.');
      final piece = pieces.single;
      if (conference['finalidade'] == 'devolucao' &&
          piece['status'] == 'vendida') {
        throw StateError('Peça vendida não pode ser devolvida.');
      }
      try {
        await tx.insert('consignacao_conferencia_itens', {
          'id': IdGenerator.temporal(),
          'comercio_id': _commerce,
          'conferencia_id': conferenciaId,
          'peca_unica_id': pecaId,
          'resultado': resultado,
          'leitura_original': leituraOriginal,
          'observacao': observacao.trim(),
          'responsavel_id': _user,
          'registrado_em': DateTime.now().toUtc().toIso8601String(),
        });
      } on DatabaseException catch (error) {
        if (error.isUniqueConstraintError()) return false;
        rethrow;
      }
      if (conference['finalidade'] == 'devolucao' &&
          const {'conferida', 'devolvida'}.contains(resultado)) {
        await tx.update(
          'pecas_unicas',
          {'status': 'devolvida'},
          where: 'id=? AND comercio_id=?',
          whereArgs: [pecaId, _commerce],
        );
        await tx.insert('consignacao_eventos', {
          'id': IdGenerator.temporal(),
          'comercio_id': _commerce,
          'consignacao_id': conference['consignacao_id'],
          'peca_id': pecaId,
          'tipo': 'devolucao',
          'quantidade': 1,
          'valor': piece['preco'],
          'observacoes': observacao.trim(),
          'criado_em': DateTime.now().toUtc().toIso8601String(),
        });
      }
      final count =
          Sqflite.firstIntValue(
            await tx.rawQuery(
              'SELECT COUNT(*) FROM consignacao_conferencia_itens WHERE conferencia_id=?',
              [conferenciaId],
            ),
          ) ??
          0;
      final expected = (conference['esperado'] as num).toInt();
      await tx.update(
        'consignacao_conferencias',
        {
          'status': 'em_andamento',
          'conferido': count,
          'pendente': (expected - count).clamp(0, expected),
          'atualizado_em': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id=?',
        whereArgs: [conferenciaId],
      );
      return true;
    });
  }

  Future<void> pausar(String id) => _status(id, 'pausada');
  Future<void> reabrir(String id) => _status(id, 'em_andamento');

  Future<void> finalizar(String id) async {
    final current = await carregar(id);
    if ((current['pendente'] as num).toInt() > 0) {
      throw StateError('Classifique as peças pendentes antes de finalizar.');
    }
    await _status(id, 'finalizada', finalized: true);
  }

  Future<void> _status(
    String id,
    String status, {
    bool finalized = false,
  }) async {
    final db = await _databaseProvider();
    final now = DateTime.now().toUtc().toIso8601String();
    final changed = await db.update(
      'consignacao_conferencias',
      {
        'status': status,
        'atualizado_em': now,
        if (finalized) 'finalizado_em': now,
      },
      where: 'id=? AND comercio_id=?',
      whereArgs: [id, _commerce],
    );
    if (changed == 0) throw StateError('Conferência não encontrada.');
  }
}
