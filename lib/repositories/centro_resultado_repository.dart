import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/utils/id_generator.dart';
import '../database/database_service.dart';
import '../models/domain/centro_resultado.dart';
import '../services/session_controller.dart';

class CentroResultadoRepository {
  final Future<Database> Function() _databaseProvider;
  final String? _commerceOverride;

  CentroResultadoRepository({
    Future<Database> Function()? databaseProvider,
    String? comercioId,
  }) : _databaseProvider =
           databaseProvider ?? (() => DatabaseService.instance.database),
       _commerceOverride = comercioId;

  String get _comercioId =>
      _commerceOverride ??
      SessionController.instance.usuario?.comercioId ??
      (throw StateError('Sessão não autenticada.'));

  Future<ResumoCentroResultado> resumo(
    CentroResultado centro,
    PeriodoGestao periodo,
  ) async {
    final db = await _databaseProvider();
    final args = <Object?>[
      _comercioId,
      periodo.inicio.toIso8601String(),
      periodo.fimExclusivo.toIso8601String(),
    ];

    final salonBilling = centro == CentroResultado.loja
        ? _zero
        : await _salaoFaturamento(db, args);
    final storeBilling = centro == CentroResultado.salao
        ? _zero
        : await _lojaFaturamento(db, args);
    final movements = await _movimentos(db, centro, periodo);
    final costs = await _custos(db, centro, periodo);
    final commissions = await _comissoes(db, centro, periodo);
    final receivable = await _aReceber(db, centro, periodo);

    final faturamento =
        salonBilling.$1 +
        storeBilling.$1 +
        (centro == CentroResultado.geral
            ? movements.administrativoReceitas +
                  movements.naoClassificadosReceitas
            : 0);
    final quantity = salonBilling.$2 + storeBilling.$2;
    final result = faturamento - costs.$1 - commissions - movements.despesas;
    final missing = <String>{...costs.$2};
    if (movements.naoClassificadosVolume > 0) {
      missing.add('Existem lançamentos financeiros não classificados.');
    }

    return ResumoCentroResultado(
      centro: centro,
      periodo: periodo,
      faturamento: faturamento,
      recebido: movements.recebido,
      aReceber: receivable,
      custosConhecidos: costs.$1,
      comissoes: commissions,
      despesas: movements.despesas,
      resultado: result,
      saldoRealizado: movements.recebido - movements.saidasPagas,
      ticketMedio: quantity == 0 ? 0 : faturamento / quantity,
      quantidadeVendas: quantity,
      servicosRealizados: salonBilling.$3,
      salao: salonBilling.$1,
      loja: storeBilling.$1,
      administrativo: movements.administrativoReceitas,
      naoClassificado: movements.naoClassificadosVolume,
      registros: quantity + movements.quantidade,
      fontes: const [
        'agendamentos',
        'pacotes_vendidos',
        'pdv_vendas',
        'movimentacoes_financeiras',
        'contas_receber_loja',
        'cobrancas',
        'estoque',
        'pecas_unicas',
        'comissoes',
      ],
      dadosAusentes: missing.toList(),
      premissas: const [
        'Faturamento usa competência operacional; recebido usa caixa realizado.',
        'Custos zero são tratados como não informados, nunca como gratuitos.',
        'Despesas gerais não são rateadas entre Salão e Loja.',
      ],
    );
  }

  static const _zero = (0.0, 0, 0);

  Future<(double, int, int)> _salaoFaturamento(
    Database db,
    List<Object?> args,
  ) async {
    final services = await db.rawQuery('''SELECT
      COALESCE(SUM(MAX(a.valor_servico-a.desconto,0)),0) total,
      COUNT(*) quantidade
      FROM agendamentos a
      WHERE a.comercio_id=? AND a.inicio>=? AND a.inicio<?
        AND a.status='concluido' AND a.excluido=0
        AND NOT EXISTS (SELECT 1 FROM sessoes_pacotes sp
          WHERE sp.agendamento_id=a.id)''', args);
    final packages = await db.rawQuery(
      '''SELECT COALESCE(SUM(valor_final),0) total,
      COUNT(*) quantidade FROM pacotes_vendidos
      WHERE business_id=? AND data_venda>=? AND data_venda<?
        AND status!='cancelado' AND deleted_at IS NULL''',
      args,
    );
    final serviceTotal = _number(services.single['total']);
    final serviceCount = _integer(services.single['quantidade']);
    return (
      serviceTotal + _number(packages.single['total']),
      serviceCount + _integer(packages.single['quantidade']),
      serviceCount,
    );
  }

  Future<(double, int, int)> _lojaFaturamento(
    Database db,
    List<Object?> args,
  ) async {
    final rows = await db.rawQuery('''SELECT COALESCE(SUM(valor_total),0) total,
      COUNT(*) quantidade FROM pdv_vendas
      WHERE comercio_id=? AND data_venda>=? AND data_venda<?
        AND status NOT IN ('cancelada','estornada')''', args);
    return (
      _number(rows.single['total']),
      _integer(rows.single['quantidade']),
      0,
    );
  }

  Future<_MovementSummary> _movimentos(
    Database db,
    CentroResultado centro,
    PeriodoGestao periodo,
  ) async {
    final whereCentro = switch (centro) {
      CentroResultado.geral => '',
      CentroResultado.salao => "AND centro_resultado='salao'",
      CentroResultado.loja => "AND centro_resultado='loja'",
      CentroResultado.naoClassificado => 'AND centro_resultado IS NULL',
    };
    final rows = await db.rawQuery(
      '''SELECT tipo,status,valor,centro_resultado
      FROM movimentacoes_financeiras WHERE comercio_id=? AND data>=? AND data<?
      $whereCentro''',
      [
        _comercioId,
        periodo.inicio.toIso8601String(),
        periodo.fimExclusivo.toIso8601String(),
      ],
    );
    var received = 0.0;
    var expenses = 0.0;
    var paidOut = 0.0;
    var administrative = 0.0;
    var unclassified = 0.0;
    var unclassifiedVolume = 0.0;
    for (final row in rows) {
      final type = '${row['tipo']}';
      final status = '${row['status']}';
      final value = _number(row['valor']);
      final incoming =
          type == 'entrada' || type == 'receita' || type == 'estorno';
      final outgoing = type == 'saida' || type == 'despesa';
      // Um recebimento estornado permanece no histórico e seu
      // contramovimento negativo neutraliza o caixa realizado.
      if ((status == 'pago' || status == 'estornado') && incoming) {
        received += value;
      }
      if (outgoing) {
        expenses += value;
        if (status == 'pago') paidOut += value;
      }
      if (incoming && row['centro_resultado'] == 'geral') {
        administrative += value;
      }
      if (incoming && row['centro_resultado'] == null) unclassified += value;
      if (row['centro_resultado'] == null) unclassifiedVolume += value.abs();
    }
    return _MovementSummary(
      recebido: received,
      despesas: expenses,
      saidasPagas: paidOut,
      administrativoReceitas: administrative,
      naoClassificadosReceitas: unclassified,
      naoClassificadosVolume: unclassifiedVolume,
      quantidade: rows.length,
    );
  }

  Future<double> _aReceber(
    Database db,
    CentroResultado centro,
    PeriodoGestao periodo,
  ) async {
    var total = 0.0;
    if (centro != CentroResultado.salao &&
        centro != CentroResultado.naoClassificado) {
      final store = await db.rawQuery(
        '''SELECT
        COALESCE(SUM(MAX(valor_total-valor_recebido,0)),0) total
        FROM contas_receber_loja WHERE comercio_id=?
          AND vencimento>=? AND vencimento<? AND status NOT IN ('paga','estornada')''',
        [
          _comercioId,
          periodo.inicio.toIso8601String(),
          periodo.fimExclusivo.toIso8601String(),
        ],
      );
      total += _number(store.single['total']);
    }
    if (centro != CentroResultado.loja &&
        centro != CentroResultado.naoClassificado) {
      final services = await db.rawQuery(
        '''SELECT COALESCE(SUM(MAX(
        a.valor_servico-a.desconto-a.valor_recebido,0)),0) total
        FROM agendamentos a WHERE a.comercio_id=?
          AND a.inicio>=? AND a.inicio<? AND a.status='concluido'
          AND a.excluido=0 AND COALESCE(a.forma_pagamento,'')!='Pacote'
          AND NOT EXISTS (SELECT 1 FROM sessoes_pacotes sp
            WHERE sp.agendamento_id=a.id)''',
        [
          _comercioId,
          periodo.inicio.toIso8601String(),
          periodo.fimExclusivo.toIso8601String(),
        ],
      );
      total += _number(services.single['total']);
      final packages = await db.rawQuery(
        '''SELECT COALESCE(SUM(MAX(
        pv.valor_final-COALESCE((SELECT SUM(m.valor)
          FROM movimentacoes_financeiras m
          WHERE m.comercio_id=pv.business_id AND m.status='pago'
            AND m.observacoes='pacote_venda_id=' || pv.id),0),0)),0) total
        FROM pacotes_vendidos pv WHERE pv.business_id=?
          AND pv.data_venda>=? AND pv.data_venda<?
          AND pv.status!='cancelado' AND pv.deleted_at IS NULL''',
        [
          _comercioId,
          periodo.inicio.toIso8601String(),
          periodo.fimExclusivo.toIso8601String(),
        ],
      );
      total += _number(packages.single['total']);
    }
    return total;
  }

  Future<(double, List<String>)> _custos(
    Database db,
    CentroResultado centro,
    PeriodoGestao periodo,
  ) async {
    var total = 0.0;
    final missing = <String>[];
    if (centro != CentroResultado.salao &&
        centro != CentroResultado.naoClassificado) {
      final rows = await db.rawQuery(
        '''SELECT vi.quantidade,
        COALESCE(e.custo_unitario,p.custo,0) custo
        FROM pdv_venda_itens vi JOIN pdv_vendas v ON v.id=vi.pdv_venda_id
        LEFT JOIN estoque e ON e.id=vi.produto_id
        LEFT JOIN pecas_unicas p ON p.id=vi.produto_id
        WHERE v.comercio_id=? AND v.data_venda>=? AND v.data_venda<?
          AND v.status NOT IN ('cancelada','estornada')''',
        [
          _comercioId,
          periodo.inicio.toIso8601String(),
          periodo.fimExclusivo.toIso8601String(),
        ],
      );
      for (final row in rows) {
        final cost = _number(row['custo']);
        if (cost <= 0) {
          missing.add('Há produtos vendidos sem custo cadastrado.');
        }
        total += _number(row['quantidade']) * cost;
      }
    }
    if (centro != CentroResultado.loja &&
        centro != CentroResultado.naoClassificado) {
      final rows = await db.rawQuery(
        '''SELECT ac.quantidade,e.custo_unitario
        FROM auditoria_estoque_consumo ac
        JOIN estoque e ON e.id=ac.estoque_id
        WHERE ac.comercio_id=? AND ac.data_hora>=? AND ac.data_hora<?
          AND ac.tipo_movimento='baixa' ''',
        [
          _comercioId,
          periodo.inicio.toIso8601String(),
          periodo.fimExclusivo.toIso8601String(),
        ],
      );
      for (final row in rows) {
        final cost = _number(row['custo_unitario']);
        if (cost <= 0) {
          missing.add('Há materiais consumidos sem custo cadastrado.');
        }
        total += _number(row['quantidade']) * cost;
      }
    }
    return (total, missing);
  }

  Future<double> _comissoes(
    Database db,
    CentroResultado centro,
    PeriodoGestao periodo,
  ) async {
    var total = 0.0;
    final args = [
      _comercioId,
      periodo.inicio.toIso8601String(),
      periodo.fimExclusivo.toIso8601String(),
    ];
    if (centro != CentroResultado.loja &&
        centro != CentroResultado.naoClassificado) {
      final services = await db.rawQuery(
        '''SELECT COALESCE(SUM(c.valor_comissao),0) total
        FROM comissoes c JOIN agendamentos a ON a.id=c.agendamento_id
        WHERE a.comercio_id=? AND c.data_geracao>=? AND c.data_geracao<?
          AND c.status!='estornada' AND c.servico_id!='pdv' ''',
        args,
      );
      total += _number(services.single['total']);
      final packages = await db.rawQuery(
        '''SELECT COALESCE(SUM(valor_comissao),0) total
        FROM pacote_comissoes WHERE comercio_id=? AND criada_em>=? AND criada_em<?
          AND status!='estornada' ''',
        args,
      );
      total += _number(packages.single['total']);
    }
    if (centro != CentroResultado.salao &&
        centro != CentroResultado.naoClassificado) {
      final store = await db.rawQuery('''SELECT COALESCE(SUM(valor),0) total
        FROM comanda_comissoes WHERE comercio_id=? AND criado_em>=? AND criado_em<?
          AND status!='estornada' ''', args);
      total += _number(store.single['total']);
      final pdv = await db.rawQuery(
        '''SELECT COALESCE(SUM(c.valor_comissao),0) total
        FROM comissoes c JOIN pdv_vendas v ON v.id=c.agendamento_id
        WHERE v.comercio_id=? AND c.data_geracao>=? AND c.data_geracao<?
          AND c.status!='estornada' AND c.servico_id='pdv' ''',
        args,
      );
      total += _number(pdv.single['total']);
    }
    return total;
  }

  Future<List<DetalheCentroResultado>> movimentos({
    required CentroResultado centro,
    required PeriodoGestao periodo,
    String? tipo,
  }) async {
    final db = await _databaseProvider();
    if (tipo == 'faturamento') {
      return _detalharFaturamento(db, centro, periodo);
    }
    if (tipo == 'a_receber') {
      return _detalharAReceber(db, centro, periodo);
    }
    final conditions = <String>[
      'comercio_id=?',
      'data>=?',
      'data<?',
      if (centro == CentroResultado.naoClassificado)
        'centro_resultado IS NULL'
      else if (centro != CentroResultado.geral)
        'centro_resultado=?',
      if (tipo == 'recebido')
        "tipo IN ('entrada','receita','estorno') AND status='pago'",
      if (tipo == 'despesas') "tipo IN ('saida','despesa')",
    ];
    final args = <Object?>[
      _comercioId,
      periodo.inicio.toIso8601String(),
      periodo.fimExclusivo.toIso8601String(),
      if (centro != CentroResultado.geral &&
          centro != CentroResultado.naoClassificado)
        centro.name,
    ];
    final rows = await db.query(
      'movimentacoes_financeiras',
      where: conditions.join(' AND '),
      whereArgs: args,
      orderBy: 'data DESC',
    );
    return rows.map((row) {
      final value = '${row['centro_resultado']}';
      return DetalheCentroResultado(
        id: '${row['id']}',
        titulo: '${row['descricao']}',
        valor: _number(row['valor']),
        data: DateTime.tryParse('${row['data']}') ?? DateTime.now(),
        centro: row['centro_resultado'] == null
            ? CentroResultado.naoClassificado
            : CentroResultado.values.firstWhere(
                (item) => item.name == value,
                orElse: () => CentroResultado.naoClassificado,
              ),
        fonte: '${row['entidade_origem'] ?? 'movimentacao_financeira'}',
        entidadeId: row['entidade_origem_id'] as String?,
        status: '${row['status']}',
      );
    }).toList();
  }

  Future<List<DetalheCentroResultado>> _detalharFaturamento(
    Database db,
    CentroResultado centro,
    PeriodoGestao periodo,
  ) async {
    final result = <DetalheCentroResultado>[];
    final args = <Object?>[
      _comercioId,
      periodo.inicio.toIso8601String(),
      periodo.fimExclusivo.toIso8601String(),
    ];
    if (centro != CentroResultado.loja &&
        centro != CentroResultado.naoClassificado) {
      final services = await db.rawQuery('''SELECT a.id,a.inicio data,
        MAX(a.valor_servico-a.desconto,0) valor,s.nome
        FROM agendamentos a LEFT JOIN servicos s ON s.id=a.servico_id
        WHERE a.comercio_id=? AND a.inicio>=? AND a.inicio<?
          AND a.status='concluido' AND a.excluido=0
          AND NOT EXISTS (SELECT 1 FROM sessoes_pacotes sp
            WHERE sp.agendamento_id=a.id)''', args);
      result.addAll(
        services.map(
          (row) => _detail(
            row,
            title: '${row['nome'] ?? 'Serviço realizado'}',
            source: 'agendamento',
            center: CentroResultado.salao,
          ),
        ),
      );
      final packages = await db.rawQuery('''SELECT pv.id,pv.data_venda data,
        pv.valor_final valor,p.nome FROM pacotes_vendidos pv
        LEFT JOIN pacotes p ON p.id=pv.pacote_id
        WHERE pv.business_id=? AND pv.data_venda>=? AND pv.data_venda<?
          AND pv.status!='cancelado' AND pv.deleted_at IS NULL''', args);
      result.addAll(
        packages.map(
          (row) => _detail(
            row,
            title: '${row['nome'] ?? 'Pacote vendido'}',
            source: 'pacote_venda',
            center: CentroResultado.salao,
          ),
        ),
      );
    }
    if (centro != CentroResultado.salao &&
        centro != CentroResultado.naoClassificado) {
      final sales = await db.rawQuery('''SELECT id,data_venda data,
        valor_total valor FROM pdv_vendas WHERE comercio_id=?
        AND data_venda>=? AND data_venda<?
        AND status NOT IN ('cancelada','estornada')''', args);
      result.addAll(
        sales.map(
          (row) => _detail(
            row,
            title: 'Venda ${row['id']}',
            source: 'pdv_venda',
            center: CentroResultado.loja,
          ),
        ),
      );
    }
    if (centro == CentroResultado.geral ||
        centro == CentroResultado.naoClassificado) {
      final extra = await movimentos(
        centro: centro == CentroResultado.naoClassificado
            ? CentroResultado.naoClassificado
            : CentroResultado.geral,
        periodo: periodo,
        tipo: 'recebido',
      );
      result.addAll(
        extra.where(
          (item) =>
              item.centro == CentroResultado.geral ||
              item.centro == CentroResultado.naoClassificado,
        ),
      );
    }
    result.sort((a, b) => b.data.compareTo(a.data));
    return result;
  }

  Future<List<DetalheCentroResultado>> _detalharAReceber(
    Database db,
    CentroResultado centro,
    PeriodoGestao periodo,
  ) async {
    final result = <DetalheCentroResultado>[];
    if (centro != CentroResultado.salao &&
        centro != CentroResultado.naoClassificado) {
      final rows = await db.rawQuery(
        '''SELECT id,vencimento data,
        MAX(valor_total-valor_recebido,0) valor FROM contas_receber_loja
        WHERE comercio_id=? AND vencimento>=? AND vencimento<?
          AND status NOT IN ('paga','estornada')''',
        [
          _comercioId,
          periodo.inicio.toIso8601String(),
          periodo.fimExclusivo.toIso8601String(),
        ],
      );
      result.addAll(
        rows.map(
          (row) => _detail(
            row,
            title: 'Conta a receber da Loja',
            source: 'conta_receber_loja',
            center: CentroResultado.loja,
          ),
        ),
      );
    }
    if (centro != CentroResultado.loja &&
        centro != CentroResultado.naoClassificado) {
      final rows = await db.rawQuery(
        '''SELECT id,criado_em data,valor
        FROM cobrancas WHERE comercio_id=? AND criado_em>=? AND criado_em<?
          AND status='pendente' AND agendamento_id IS NOT NULL''',
        [
          _comercioId,
          periodo.inicio.toIso8601String(),
          periodo.fimExclusivo.toIso8601String(),
        ],
      );
      result.addAll(
        rows.map(
          (row) => _detail(
            row,
            title: 'Cobrança pendente',
            source: 'cobranca',
            center: CentroResultado.salao,
          ),
        ),
      );
    }
    return result;
  }

  DetalheCentroResultado _detail(
    Map<String, Object?> row, {
    required String title,
    required String source,
    required CentroResultado center,
  }) => DetalheCentroResultado(
    id: '${row['id']}',
    titulo: title,
    valor: _number(row['valor']),
    data: DateTime.tryParse('${row['data']}') ?? DateTime.now(),
    centro: center,
    fonte: source,
    entidadeId: '${row['id']}',
    status: 'competência',
  );

  Future<void> classificarMovimento(
    String movimentoId,
    CentroResultado centro,
  ) async {
    if (centro == CentroResultado.naoClassificado) {
      throw ArgumentError('Selecione Salão, Loja ou Geral.');
    }
    final user = SessionController.instance.usuario;
    if (user == null || user.comercioId != _comercioId) {
      throw StateError('Sessão não autenticada.');
    }
    final db = await _databaseProvider();
    await db.transaction((tx) async {
      final rows = await tx.query(
        'movimentacoes_financeiras',
        columns: ['centro_resultado'],
        where: 'id=? AND comercio_id=?',
        whereArgs: [movimentoId, _comercioId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Lançamento não encontrado.');
      final before = rows.single['centro_resultado'];
      await tx.update(
        'movimentacoes_financeiras',
        {'centro_resultado': centro.name},
        where: 'id=? AND comercio_id=?',
        whereArgs: [movimentoId, _comercioId],
      );
      await tx.insert('undo_auditoria', {
        'id': IdGenerator.temporal(),
        'comercio_id': _comercioId,
        'usuario_id': user.id,
        'entidade': 'movimentacao_financeira',
        'entidade_id': movimentoId,
        'acao': 'classificar_centro_resultado',
        'estado_anterior': jsonEncode({'centro_resultado': before}),
        'estado_novo': jsonEncode({'centro_resultado': centro.name}),
        'criado_em': DateTime.now().toUtc().toIso8601String(),
      });
    });
  }

  static double _number(Object? value) => (value as num? ?? 0).toDouble();
  static int _integer(Object? value) => (value as num? ?? 0).toInt();
}

class _MovementSummary {
  final double recebido;
  final double despesas;
  final double saidasPagas;
  final double administrativoReceitas;
  final double naoClassificadosReceitas;
  final double naoClassificadosVolume;
  final int quantidade;

  const _MovementSummary({
    required this.recebido,
    required this.despesas,
    required this.saidasPagas,
    required this.administrativoReceitas,
    required this.naoClassificadosReceitas,
    required this.naoClassificadosVolume,
    required this.quantidade,
  });
}
