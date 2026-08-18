import 'package:sqflite/sqflite.dart';

import '../database/database_service.dart';
import '../services/session_controller.dart';

class CentralComandasRepository {
  final Future<Database> Function() _databaseProvider;
  final String? _comercioOverride;

  CentralComandasRepository({
    Future<Database> Function()? databaseProvider,
    String? comercioId,
  }) : _databaseProvider =
           databaseProvider ?? (() => DatabaseService.instance.database),
       _comercioOverride = comercioId;

  String get _comercio =>
      _comercioOverride ?? SessionController.instance.usuario!.comercioId;

  Future<List<Map<String, Object?>>> listar({
    String? filtro,
    String pesquisa = '',
    String? clienteId,
    DateTime? de,
    DateTime? ate,
    String? formaPagamento,
  }) async {
    final db = await _databaseProvider();
    final comandas = await db.rawQuery(
      '''SELECT c.*, 'comanda' origem_registro,
        COALESCE(cl.nome, 'Cliente não vinculado') cliente_nome,
        COALESCE(cl.whatsapp, cl.telefone, '') cliente_telefone,
        COALESCE(c.finalizada_em, c.criado_em) data_venda,
        COALESCE((SELECT MAX(dt) FROM (
          SELECT p.registrado_em dt FROM comanda_loja_pagamentos p
            WHERE p.comanda_id=c.id AND p.status='pago'
          UNION ALL
          SELECT rp.registrado_em dt FROM contas_receber_pagamentos rp
            JOIN contas_receber_loja r ON r.id=rp.conta_id
            WHERE r.comanda_id=c.id AND rp.estornado=0)), '') data_pagamento,
        TRIM(COALESCE((SELECT GROUP_CONCAT(DISTINCT p.forma)
          FROM comanda_loja_pagamentos p WHERE p.comanda_id=c.id), '') || ',' ||
          COALESCE((SELECT GROUP_CONCAT(DISTINCT rp.forma)
            FROM contas_receber_pagamentos rp
            JOIN contas_receber_loja r ON r.id=rp.conta_id
            WHERE r.comanda_id=c.id AND rp.estornado=0), ''), ',') forma_pagamento,
        COALESCE((SELECT GROUP_CONCAT(i.nome || ' ' || COALESCE(i.codigo,''), ' ')
          FROM comanda_loja_itens i WHERE i.comanda_id=c.id), '') itens_busca
        FROM comandas_loja c
        LEFT JOIN clientes cl ON cl.id=c.cliente_id AND cl.comercio_id=c.comercio_id
        WHERE c.comercio_id=?''',
      [_comercio],
    );
    final vendas = await db.rawQuery(
      '''SELECT v.id, v.id numero, v.comercio_id, v.cliente_id,
        v.profissional_id, v.status, v.valor_total total,
        v.valor_total subtotal, 0.0 desconto, v.valor_total valor_pago,
        NULL vencimento, NULL observacoes, v.id venda_id,
        v.data_venda finalizada_em, NULL cancelada_em,
        v.data_venda criado_em, v.data_venda atualizado_em,
        'venda' origem_registro,
        COALESCE(cl.nome, 'Cliente não vinculado') cliente_nome,
        COALESCE(cl.whatsapp, cl.telefone, '') cliente_telefone,
        v.data_venda data_venda,
        COALESCE((SELECT MAX(m.data) FROM movimentacoes_financeiras m
          WHERE m.entidade_origem='pdv_venda' AND m.entidade_origem_id=v.id
            AND m.tipo='receita' AND m.status='pago'), '') data_pagamento,
        COALESCE((SELECT GROUP_CONCAT(DISTINCT m.forma_pagamento)
          FROM movimentacoes_financeiras m
          WHERE m.entidade_origem='pdv_venda' AND m.entidade_origem_id=v.id), '') forma_pagamento,
        COALESCE((SELECT GROUP_CONCAT(
          COALESCE(e.nome,p.nome,vi.produto_id) || ' ' ||
          COALESCE(e.codigo_barras,e.codigo_interno,p.codigo_exclusivo,''), ' ')
          FROM pdv_venda_itens vi
          LEFT JOIN estoque e ON e.id=vi.produto_id
          LEFT JOIN pecas_unicas p ON p.id=vi.produto_id
          WHERE vi.pdv_venda_id=v.id), '') itens_busca
        FROM pdv_vendas v
        LEFT JOIN clientes cl ON cl.id=v.cliente_id AND cl.comercio_id=v.comercio_id
        WHERE v.comercio_id=? AND NOT EXISTS (
          SELECT 1 FROM comandas_loja c
          WHERE c.comercio_id=v.comercio_id AND c.venda_id=v.id)''',
      [_comercio],
    );
    final termo = pesquisa.trim().toLowerCase();
    final from = de?.toUtc();
    final until = ate == null
        ? null
        : DateTime.utc(ate.year, ate.month, ate.day, 23, 59, 59, 999);
    final rows = <Map<String, Object?>>[...comandas, ...vendas]
        .where((row) {
          if (clienteId != null && row['cliente_id'] != clienteId) return false;
          final status = _statusCentral(row);
          if (!_aceitaFiltro(status, filtro)) return false;
          final date = DateTime.tryParse('${row['data_venda'] ?? ''}');
          if (from != null && (date == null || date.isBefore(from))) {
            return false;
          }
          if (until != null && (date == null || date.isAfter(until))) {
            return false;
          }
          if (formaPagamento != null &&
              formaPagamento.trim().isNotEmpty &&
              !'${row['forma_pagamento']}'.toLowerCase().contains(
                formaPagamento.trim().toLowerCase(),
              )) {
            return false;
          }
          if (termo.isNotEmpty) {
            final searchable = [
              row['cliente_nome'],
              row['cliente_telefone'],
              row['numero'],
              row['id'],
              row['itens_busca'],
              row['data_venda'],
              row['forma_pagamento'],
            ].join(' ').toLowerCase();
            if (!searchable.contains(termo)) return false;
          }
          return true;
        })
        .map((row) {
          final total = (row['total'] as num? ?? 0).toDouble();
          final paid = (row['valor_pago'] as num? ?? 0).toDouble();
          return {
            ...row,
            'status_central': _statusCentral(row),
            'saldo_restante': (total - paid).clamp(0, double.infinity),
            'criada_em': row['data_venda'],
            'itens': row['itens_busca'],
          };
        })
        .toList();
    rows.sort(
      (a, b) =>
          '${b['data_venda'] ?? ''}'.compareTo('${a['data_venda'] ?? ''}'),
    );
    return rows;
  }

  Future<Map<String, Object?>> detalhe(
    String id, {
    required String origem,
  }) async {
    final db = await _databaseProvider();
    final rows = await listar();
    final header = rows.where(
      (row) => row['id'] == id && row['origem_registro'] == origem,
    );
    if (header.isEmpty) throw StateError('Comanda não encontrada.');
    if (origem == 'comanda') {
      final items = await db.query(
        'comanda_loja_itens',
        where: 'comanda_id=? AND comercio_id=?',
        whereArgs: [id, _comercio],
      );
      final payments = await db.query(
        'comanda_loja_pagamentos',
        where: 'comanda_id=? AND comercio_id=?',
        whereArgs: [id, _comercio],
        orderBy: 'registrado_em',
      );
      final receivables = await db.rawQuery(
        '''SELECT rp.id, rp.forma, rp.valor,
          CASE WHEN rp.estornado=1 THEN 'estornado' ELSE 'pago' END status,
          rp.registrado_em
          FROM contas_receber_pagamentos rp
          JOIN contas_receber_loja r ON r.id=rp.conta_id
          WHERE r.comanda_id=? AND rp.comercio_id=?''',
        [id, _comercio],
      );
      final allPayments = <Map<String, Object?>>[...payments, ...receivables]
        ..sort(
          (a, b) => '${a['registrado_em']}'.compareTo('${b['registrado_em']}'),
        );
      return {...header.single, 'itens': items, 'pagamentos': allPayments};
    }
    final items = await db.rawQuery(
      '''SELECT vi.*, COALESCE(e.nome,p.nome,vi.produto_id) nome,
        COALESCE(e.codigo_barras,e.codigo_interno,p.codigo_exclusivo) codigo,
        vi.valor_unitario * vi.quantidade subtotal
        FROM pdv_venda_itens vi
        LEFT JOIN estoque e ON e.id=vi.produto_id
        LEFT JOIN pecas_unicas p ON p.id=vi.produto_id
        WHERE vi.pdv_venda_id=?''',
      [id],
    );
    final payments = await db.rawQuery(
      '''SELECT id, forma_pagamento forma, valor, status, data registrado_em
        FROM movimentacoes_financeiras
        WHERE entidade_origem='pdv_venda' AND entidade_origem_id=?
        ORDER BY data''',
      [id],
    );
    return {...header.single, 'itens': items, 'pagamentos': payments};
  }

  Future<Map<String, Object?>> resumoCliente(String clienteId) async {
    final rows = await listar(clienteId: clienteId);
    final valid = rows
        .where(
          (row) =>
              !const {'cancelada', 'estornada'}.contains(row['status_central']),
        )
        .toList();
    final total = valid.fold<double>(
      0,
      (sum, row) => sum + (row['total'] as num? ?? 0).toDouble(),
    );
    final open = valid.fold<double>(
      0,
      (sum, row) => sum + (row['saldo_restante'] as num? ?? 0).toDouble(),
    );
    return {
      'total_comprado': total,
      'quantidade_compras': valid.length,
      'ticket_medio': valid.isEmpty ? 0.0 : total / valid.length,
      'ultima_compra': valid.isEmpty ? null : valid.first['data_venda'],
      'total_em_aberto': open,
    };
  }

  static String _statusCentral(Map<String, Object?> row) {
    final raw = '${row['status']}';
    return switch (raw) {
      'aguardando_pagamento' || 'pendente' || 'vencida' => 'pendente',
      'parcialmente_paga' || 'parcial' => 'parcial',
      'concluida' => 'paga',
      _ => raw,
    };
  }

  static bool _aceitaFiltro(String status, String? filtro) => switch (filtro) {
    null || 'todas' => true,
    'abertas' => status == 'aberta',
    'pendentes' => status == 'pendente',
    'parciais' => status == 'parcial',
    'pagas' => status == 'paga',
    'canceladas' => const {'cancelada', 'estornada'}.contains(status),
    _ => status == filtro,
  };
}
