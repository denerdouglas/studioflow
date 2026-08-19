import 'package:sqflite/sqflite.dart';

import '../core/utils/id_generator.dart';
import '../database/database_service.dart';
import '../models/domain/acesso.dart';
import '../services/session_controller.dart';
import 'recebimento_servico_writer.dart';

class ContasReceberRepository {
  final Future<Database> Function() _databaseProvider;

  ContasReceberRepository({Future<Database> Function()? databaseProvider})
    : _databaseProvider =
          databaseProvider ?? (() => DatabaseService.instance.database);

  UsuarioAcesso get _user {
    final user = SessionController.instance.usuario;
    if (user == null ||
        !user.pode(ModuloPermissao.financeiro) ||
        !user.podeAcao(AcaoPermissao.acessarFinanceiro)) {
      throw StateError('Acesso ao contas a receber não autorizado.');
    }
    return user;
  }

  Future<List<Map<String, Object?>>> listar({
    String? status,
    String? clienteId,
    String? loteId,
    String? unidadeId,
    DateTime? de,
    DateTime? ate,
  }) async {
    final user = _user;
    final db = await _databaseProvider();
    final where = <String>['r.comercio_id = ?'];
    final args = <Object?>[user.comercioId];
    if (status != null) {
      where.add('r.status = ?');
      args.add(status);
    }
    if (clienteId != null) {
      where.add('r.cliente_id = ?');
      args.add(clienteId);
    }
    if (loteId != null) {
      where.add('r.lote_id = ?');
      args.add(loteId);
    }
    if (unidadeId != null) {
      where.add('r.unidade_id = ?');
      args.add(unidadeId);
    }
    if (de != null) {
      where.add('r.vencimento >= ?');
      args.add(de.toIso8601String());
    }
    if (ate != null) {
      where.add('r.vencimento <= ?');
      args.add(ate.toIso8601String());
    }
    final loja = await db.rawQuery(
      '''SELECT r.*, c.nome cliente_nome, c.whatsapp cliente_telefone,
         co.numero comanda_numero,
         'loja' origem_conta,
         (r.valor_total-r.valor_recebido) saldo,
         (SELECT MAX(p.registrado_em) FROM contas_receber_pagamentos p
           WHERE p.conta_id=r.id AND p.estornado=0) data_pagamento
         FROM contas_receber_loja r JOIN clientes c ON c.id=r.cliente_id
         LEFT JOIN comandas_loja co ON co.id=r.comanda_id
         WHERE ${where.join(' AND ')} ORDER BY r.vencimento, c.nome''',
      args,
    );
    final servicoWhere = <String>[
      'cb.comercio_id = ?',
      "cb.status IN ('pendente','parcial','confirmado_manual')",
    ];
    final servicoArgs = <Object?>[user.comercioId];
    if (status != null) {
      servicoWhere.add('cb.status = ?');
      servicoArgs.add(status);
    }
    if (clienteId != null) {
      servicoWhere.add('cb.cliente_id = ?');
      servicoArgs.add(clienteId);
    }
    if (de != null) {
      servicoWhere.add('cb.vencimento >= ?');
      servicoArgs.add(de.toIso8601String());
    }
    if (ate != null) {
      servicoWhere.add('cb.vencimento <= ?');
      servicoArgs.add(ate.toIso8601String());
    }
    final servicos = await db.rawQuery('''SELECT cb.*, cb.valor valor_total,
      c.nome cliente_nome, c.whatsapp cliente_telefone,
      NULL comanda_numero, 'servico' origem_conta,
      (cb.valor-cb.valor_recebido) saldo,
      (SELECT MAX(p.registrado_em) FROM cobranca_pagamentos p
        WHERE p.cobranca_id=cb.id AND p.estornado=0) data_pagamento
      FROM cobrancas cb JOIN clientes c ON c.id=cb.cliente_id
      WHERE ${servicoWhere.join(' AND ')}''', servicoArgs);
    final result = <Map<String, Object?>>[...loja, ...servicos];
    result.sort((a, b) => '${a['vencimento']}'.compareTo('${b['vencimento']}'));
    return result;
  }

  Future<void> registrarPagamento(
    String contaId,
    double valor,
    String forma, {
    String? observacoes,
    DateTime? dataPagamento,
  }) async {
    final user = _user;
    if (valor <= 0 || forma.trim().isEmpty) {
      throw StateError('Pagamento inválido.');
    }
    final db = await _databaseProvider();
    await db.transaction((tx) async {
      final rows = await tx.query(
        'contas_receber_loja',
        where: "id = ? AND comercio_id = ? AND status != 'paga'",
        whereArgs: [contaId, user.comercioId],
        limit: 1,
      );
      if (rows.isEmpty) {
        final serviceRows = await tx.query(
          'cobrancas',
          where: "id=? AND comercio_id=? AND status IN ('pendente','parcial')",
          whereArgs: [contaId, user.comercioId],
          limit: 1,
        );
        if (serviceRows.isEmpty) {
          throw StateError('Conta não encontrada ou já paga.');
        }
        final service = serviceRows.single;
        final received = (service['valor_recebido'] as num? ?? 0).toDouble();
        final total = (service['valor'] as num).toDouble();
        if (received + valor > total + 0.001) {
          throw StateError('Pagamento maior que o saldo.');
        }
        final paymentDate = dataPagamento ?? DateTime.now();
        final paymentId = IdGenerator.temporal();
        await RecebimentoServicoWriter.registrar(
          tx,
          comercioId: user.comercioId,
          agendamentoId: service['agendamento_id'] as String,
          valor: valor,
          formaPagamento: forma.trim(),
          referencia: paymentId,
          entidadeOrigem: 'conta_receber_servico',
          usuarioId: user.id,
          data: paymentDate,
        );
        await tx.insert('cobranca_pagamentos', {
          'id': paymentId,
          'cobranca_id': contaId,
          'comercio_id': user.comercioId,
          'valor': valor,
          'forma': forma.trim(),
          'registrado_em': paymentDate.toUtc().toIso8601String(),
        });
        final next = received + valor;
        await tx.update(
          'cobrancas',
          {
            'valor_recebido': next,
            'status': next >= total - 0.001 ? 'confirmado_manual' : 'parcial',
            if (next >= total - 0.001)
              'confirmado_em': paymentDate.toUtc().toIso8601String(),
          },
          where: 'id=? AND comercio_id=?',
          whereArgs: [contaId, user.comercioId],
        );
        return;
      }
      final account = rows.single;
      final received = (account['valor_recebido'] as num).toDouble();
      final total = (account['valor_total'] as num).toDouble();
      if (received + valor > total + 0.001) {
        throw StateError('Pagamento maior que o saldo.');
      }
      final now = (dataPagamento ?? DateTime.now()).toUtc().toIso8601String();
      final paymentId = IdGenerator.temporal();
      await tx.insert('contas_receber_pagamentos', {
        'id': paymentId,
        'conta_id': contaId,
        'comercio_id': user.comercioId,
        'valor': valor,
        'forma': forma.trim(),
        'observacoes': observacoes,
        'registrado_em': now,
      });
      final next = received + valor;
      final status = next >= total - 0.001 ? 'paga' : 'parcialmente_paga';
      await tx.update(
        'contas_receber_loja',
        {'valor_recebido': next, 'status': status, 'atualizado_em': now},
        where: 'id = ? AND comercio_id = ?',
        whereArgs: [contaId, user.comercioId],
      );
      await tx.update(
        'comandas_loja',
        {'valor_pago': next, 'status': status, 'atualizado_em': now},
        where: 'id = ? AND comercio_id = ?',
        whereArgs: [account['comanda_id'], user.comercioId],
      );
      await tx.insert('movimentacoes_financeiras', {
        'id': '${paymentId}_finance',
        'tipo': 'entrada',
        'descricao': 'Recebimento de comanda',
        'valor': valor,
        'forma_pagamento': forma.trim(),
        'status': 'pago',
        'data': now,
        'data_criacao': now,
        'categoria': 'contas a receber',
        'centro_resultado': 'loja',
        'entidade_origem': 'conta_receber_loja',
        'entidade_origem_id': contaId,
        'cliente_id': account['cliente_id'],
        'usuario_responsavel_id': user.id,
        'comercio_id': user.comercioId,
      });
    });
  }

  Future<void> alterar({
    required String contaId,
    DateTime? vencimento,
    String? formaPagamento,
    String? observacoes,
  }) async {
    final user = _user;
    final db = await _databaseProvider();
    final changed = await db.update(
      'contas_receber_loja',
      {
        if (vencimento != null)
          'vencimento': vencimento.toUtc().toIso8601String(),
        'forma_pagamento': ?formaPagamento,
        'observacoes': ?observacoes,
        'atualizado_em': DateTime.now().toUtc().toIso8601String(),
      },
      where: "id=? AND comercio_id=? AND status!='paga'",
      whereArgs: [contaId, user.comercioId],
    );
    if (changed == 0) {
      throw StateError('Conta não encontrada ou não editável.');
    }
  }

  Future<void> estornarPagamento(String pagamentoId, String motivo) async {
    final user = _user;
    if (motivo.trim().isEmpty) throw StateError('Informe o motivo do estorno.');
    final db = await _databaseProvider();
    await db.transaction((tx) async {
      final payments = await tx.query(
        'contas_receber_pagamentos',
        where: 'id=? AND comercio_id=? AND estornado=0',
        whereArgs: [pagamentoId, user.comercioId],
        limit: 1,
      );
      if (payments.isEmpty) {
        throw StateError('Pagamento não encontrado ou já estornado.');
      }
      final payment = payments.single;
      final accounts = await tx.query(
        'contas_receber_loja',
        where: 'id=? AND comercio_id=?',
        whereArgs: [payment['conta_id'], user.comercioId],
        limit: 1,
      );
      if (accounts.isEmpty) throw StateError('Conta não encontrada.');
      final account = accounts.single;
      final next =
          ((account['valor_recebido'] as num).toDouble() -
                  (payment['valor'] as num).toDouble())
              .clamp(0, double.infinity);
      final due = DateTime.parse(
        account['vencimento'] as String,
      ).isBefore(DateTime.now().toUtc());
      final status = next <= 0.001
          ? (due ? 'vencida' : 'pendente')
          : (due ? 'vencida' : 'parcialmente_paga');
      final now = DateTime.now().toUtc().toIso8601String();
      await tx.update(
        'contas_receber_pagamentos',
        {'estornado': 1, 'estornado_em': now, 'observacoes': motivo.trim()},
        where: 'id=?',
        whereArgs: [pagamentoId],
      );
      await tx.update(
        'contas_receber_loja',
        {'valor_recebido': next, 'status': status, 'atualizado_em': now},
        where: 'id=?',
        whereArgs: [account['id']],
      );
      await tx.update(
        'comandas_loja',
        {'valor_pago': next, 'status': status, 'atualizado_em': now},
        where: 'id=? AND comercio_id=?',
        whereArgs: [account['comanda_id'], user.comercioId],
      );
      await tx.insert('movimentacoes_financeiras', {
        'id': '${pagamentoId}_estorno',
        'tipo': 'saida',
        'descricao': 'Estorno de conta a receber: ${motivo.trim()}',
        'valor': (payment['valor'] as num).toDouble().abs(),
        'forma_pagamento': payment['forma'],
        'status': 'pago',
        'data': now,
        'data_criacao': now,
        'categoria': 'contas a receber',
        'centro_resultado': 'loja',
        'entidade_origem': 'conta_receber_loja',
        'entidade_origem_id': account['id'],
        'cliente_id': account['cliente_id'],
        'usuario_responsavel_id': user.id,
        'comercio_id': user.comercioId,
      });
    });
  }

  static DateTime calcularVencimento({
    required DateTime referencia,
    required String tipo,
    int? dias,
    int? diaFixo,
    int? vencimentoDia,
  }) {
    final base = DateTime.utc(
      referencia.year,
      referencia.month,
      referencia.day,
    );
    switch (tipo) {
      case 'imediato':
        return base;
      case 'dias':
        return base.add(Duration(days: dias ?? 0));
      case 'dia_fixo':
        final day = (diaFixo ?? 1).clamp(1, 28);
        var result = DateTime.utc(base.year, base.month, day);
        if (result.isBefore(base)) {
          result = DateTime.utc(base.year, base.month + 1, day);
        }
        return result;
      case 'ciclo_maleta':
        final day = (vencimentoDia ?? 5).clamp(1, 28);
        return DateTime.utc(base.year, base.month + 2, day);
      default:
        throw StateError('Regra de cobrança inválida.');
    }
  }

  Future<void> atualizarVencidas({DateTime? agora}) async {
    final user = _user;
    final db = await _databaseProvider();
    await db.rawUpdate(
      "UPDATE contas_receber_loja SET status='vencida', atualizado_em=? "
      "WHERE comercio_id=? AND status IN ('pendente','parcialmente_paga') AND vencimento < ?",
      [
        DateTime.now().toUtc().toIso8601String(),
        user.comercioId,
        (agora ?? DateTime.now()).toUtc().toIso8601String(),
      ],
    );
  }
}
