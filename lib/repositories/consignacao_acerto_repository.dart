import 'package:sqflite/sqflite.dart';

import '../core/utils/id_generator.dart';
import '../database/database_service.dart';
import '../services/session_controller.dart';

class ConsignacaoAcertoInput {
  final String? responsavelId;
  final int? quantidadeFornecedor;
  final double? valorFornecedor;
  final double? comissaoPercentual;
  final double? comissaoValor;
  final double repasse;
  final double desconto;
  final double taxas;
  final double ajustes;
  final double perdasFinanceiras;
  final DateTime? dataAcerto;
  final DateTime? dataPagamento;
  final String observacoes;
  final bool confirmarDivergencia;

  const ConsignacaoAcertoInput({
    this.responsavelId,
    this.quantidadeFornecedor,
    this.valorFornecedor,
    this.comissaoPercentual,
    this.comissaoValor,
    this.repasse = 0,
    this.desconto = 0,
    this.taxas = 0,
    this.ajustes = 0,
    this.perdasFinanceiras = 0,
    this.dataAcerto,
    this.dataPagamento,
    this.observacoes = '',
    this.confirmarDivergencia = false,
  });
}

class ConsignacaoAcertoRepository {
  final Future<Database> Function() _databaseProvider;
  final String? _commerceOverride;
  final String? _userOverride;

  ConsignacaoAcertoRepository({
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
  String get responsavelAtual => _user;

  Future<Map<String, Object?>> resumoRemessa(String remessaId) async {
    final db = await _databaseProvider();
    return _summary(db, remessaId);
  }

  Future<Map<String, Object?>?> carregar(String remessaId) async {
    final db = await _databaseProvider();
    final rows = await db.query(
      'consignacao_acertos',
      where: 'comercio_id=? AND consignacao_id=?',
      whereArgs: [_commerce, remessaId],
      limit: 1,
    );
    return rows.firstOrNull;
  }

  Future<Map<String, Object?>> salvar(
    String remessaId,
    ConsignacaoAcertoInput input,
  ) async {
    final db = await _databaseProvider();
    return db.transaction((tx) async {
      final summary = await _summary(tx, remessaId);
      final soldCount = (summary['vendidas'] as num).toInt();
      final soldValue = (summary['valor_vendido'] as num).toDouble();
      final returned = (summary['devolvidas'] as num).toInt();
      final received = (summary['recebidas'] as num).toInt();
      final losses = (summary['perdas'] as num).toInt();
      final supplierCount = input.quantidadeFornecedor;
      final supplierValue = input.valorFornecedor;
      final divergenceCount = supplierCount == null
          ? null
          : supplierCount - soldCount;
      final divergenceValue = supplierValue == null
          ? null
          : supplierValue - soldValue;
      final diverges =
          (divergenceCount ?? 0) != 0 || (divergenceValue ?? 0).abs() > 0.005;
      if (diverges && !input.confirmarDivergencia) {
        throw StateError('Confirme a divergência antes de prosseguir.');
      }
      final commission =
          input.comissaoValor ??
          (input.comissaoPercentual == null
              ? 0.0
              : soldValue * input.comissaoPercentual! / 100);
      final net =
          soldValue -
          input.repasse -
          input.perdasFinanceiras -
          input.taxas +
          input.desconto +
          input.ajustes;
      final now = DateTime.now().toUtc().toIso8601String();
      final existing = await tx.query(
        'consignacao_acertos',
        where: 'comercio_id=? AND consignacao_id=?',
        whereArgs: [_commerce, remessaId],
        limit: 1,
      );
      if (existing.isNotEmpty &&
          const {'pago', 'fechado'}.contains(existing.single['status'])) {
        throw StateError('Reabra o acerto antes de alterá-lo.');
      }
      final id =
          existing.firstOrNull?['id'] as String? ?? IdGenerator.temporal();
      final values = <String, Object?>{
        'id': id,
        'comercio_id': _commerce,
        'consignacao_id': remessaId,
        'quantidade_recebida': received,
        'quantidade_vendida': soldCount,
        'quantidade_devolvida': returned,
        'quantidade_perdas': losses,
        'valor_vendido_sistema': soldValue,
        'quantidade_fornecedor': supplierCount,
        'valor_fornecedor': supplierValue,
        'comissao_percentual': input.comissaoPercentual,
        'comissao_valor': commission,
        'repasse': input.repasse,
        'desconto': input.desconto,
        'taxas': input.taxas,
        'ajustes': input.ajustes,
        'perdas_financeiras': input.perdasFinanceiras,
        'resultado_liquido': net,
        'divergencia_quantidade': divergenceCount,
        'divergencia_valor': divergenceValue,
        'divergencia_confirmada': diverges ? 1 : 0,
        'data_acerto': input.dataAcerto?.toUtc().toIso8601String(),
        'data_pagamento': input.dataPagamento?.toUtc().toIso8601String(),
        'observacoes': input.observacoes.trim(),
        'status': 'em_conferencia',
        'responsavel_id': input.responsavelId?.trim().isNotEmpty == true
            ? input.responsavelId!.trim()
            : _user,
        'criado_em': existing.firstOrNull?['criado_em'] ?? now,
        'atualizado_em': now,
      };
      await tx.insert(
        'consignacao_acertos',
        values,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await tx.update(
        'consignacoes',
        {'acerto_status': 'em_conferencia'},
        where: 'id=? AND comercio_id=?',
        whereArgs: [remessaId, _commerce],
      );
      return values;
    });
  }

  Future<void> marcarConferido(String acertoId) =>
      _changeStatus(acertoId, 'conferido');

  Future<void> pagar(String acertoId) async {
    final db = await _databaseProvider();
    await db.transaction((tx) async {
      final rows = await tx.query(
        'consignacao_acertos',
        where: 'id=? AND comercio_id=?',
        whereArgs: [acertoId, _commerce],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Acerto não encontrado.');
      final settlement = rows.single;
      if (!const {
        'conferido',
        'pago',
        'fechado',
      }.contains(settlement['status'])) {
        throw StateError('Confira o acerto antes de pagar.');
      }
      final movement = await tx.query(
        'movimentacoes_financeiras',
        columns: ['id'],
        where: 'comercio_id=? AND entidade_origem=? AND entidade_origem_id=?',
        whereArgs: [_commerce, 'consignacao_acerto', acertoId],
        limit: 1,
      );
      if (movement.isEmpty) {
        final outflow =
            (settlement['valor_vendido_sistema'] as num).toDouble() -
            (settlement['resultado_liquido'] as num).toDouble();
        if (outflow > 0.005) {
          final now = DateTime.now().toUtc().toIso8601String();
          await tx.insert('movimentacoes_financeiras', {
            'id': 'acerto_financeiro_$acertoId',
            'comercio_id': _commerce,
            'tipo': 'saida',
            'descricao': 'Acerto de remessa consignada',
            'valor': outflow,
            'forma_pagamento': 'acerto_fornecedor',
            'status': 'pago',
            'data': now,
            'data_criacao': now,
            'categoria': 'Repasse de consignação',
            'usuario_responsavel_id': _user,
            'observacoes': 'consignacao_id=${settlement['consignacao_id']}',
            'centro_resultado': 'loja',
            'entidade_origem': 'consignacao_acerto',
            'entidade_origem_id': acertoId,
          });
        }
      }
      await _updateStatus(tx, settlement, 'pago');
    });
  }

  Future<void> fechar(String acertoId) => _changeStatus(acertoId, 'fechado');
  Future<void> reabrir(String acertoId) =>
      _changeStatus(acertoId, 'em_conferencia');

  Future<void> _changeStatus(String id, String status) async {
    final db = await _databaseProvider();
    await db.transaction((tx) async {
      final rows = await tx.query(
        'consignacao_acertos',
        where: 'id=? AND comercio_id=?',
        whereArgs: [id, _commerce],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Acerto não encontrado.');
      await _updateStatus(tx, rows.single, status);
    });
  }

  Future<void> _updateStatus(
    DatabaseExecutor tx,
    Map<String, Object?> settlement,
    String status,
  ) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await tx.update(
      'consignacao_acertos',
      {'status': status, 'atualizado_em': now},
      where: 'id=? AND comercio_id=?',
      whereArgs: [settlement['id'], _commerce],
    );
    await tx.update(
      'consignacoes',
      {'acerto_status': status},
      where: 'id=? AND comercio_id=?',
      whereArgs: [settlement['consignacao_id'], _commerce],
    );
  }

  Future<Map<String, Object?>> _summary(
    DatabaseExecutor db,
    String remessaId,
  ) async {
    final rows = await db.rawQuery(
      '''SELECT COUNT(*) recebidas,
      SUM(CASE WHEN status='vendida' THEN 1 ELSE 0 END) vendidas,
      SUM(CASE WHEN status='devolvida' THEN 1 ELSE 0 END) devolvidas,
      SUM(CASE WHEN status IN ('perdida','roubada','avariada') THEN 1 ELSE 0 END) perdas,
      COALESCE(SUM(CASE WHEN status='vendida' THEN
        COALESCE((SELECT valor FROM consignacao_eventos e
          WHERE e.peca_id=p.id AND e.tipo='venda'
          ORDER BY criado_em DESC LIMIT 1),preco) ELSE 0 END),0) valor_vendido
      FROM pecas_unicas p WHERE comercio_id=? AND lote_id=?''',
      [_commerce, remessaId],
    );
    if (rows.isEmpty || (rows.single['recebidas'] as num).toInt() == 0) {
      throw StateError('Remessa sem peças.');
    }
    return rows.single;
  }
}
