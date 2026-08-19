import 'package:sqflite/sqflite.dart';

import '../core/utils/id_generator.dart';
import '../database/database_service.dart';
import '../models/domain/acesso.dart';
import '../services/session_controller.dart';
import '../services/purchase_receipt_service.dart';

class ComandaLojaRepository {
  final Future<Database> Function() _databaseProvider;

  ComandaLojaRepository({Future<Database> Function()? databaseProvider})
    : _databaseProvider =
          databaseProvider ?? (() => DatabaseService.instance.database);

  UsuarioAcesso _require(AcaoPermissao action) {
    final user = SessionController.instance.usuario;
    if (user == null ||
        !user.pode(ModuloPermissao.lojaSalao) ||
        !user.podeAcao(action)) {
      throw StateError('Ação não autorizada para a Loja do Salão.');
    }
    return user;
  }

  Future<String> criar({
    required String clienteId,
    String? unidadeId,
    String? profissionalId,
    DateTime? vencimento,
    String? observacoes,
  }) async {
    final user = _require(AcaoPermissao.realizarVenda);
    final db = await _databaseProvider();
    final client = await db.query(
      'clientes',
      columns: ['id'],
      where: 'id = ? AND comercio_id = ? AND ativo = 1',
      whereArgs: [clienteId, user.comercioId],
      limit: 1,
    );
    if (client.isEmpty) throw StateError('Cliente não encontrado.');
    final now = DateTime.now().toUtc();
    final id = IdGenerator.temporal();
    final count =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM comandas_loja WHERE comercio_id = ?',
            [user.comercioId],
          ),
        ) ??
        0;
    await db.insert('comandas_loja', {
      'id': id,
      'numero': '${now.year}${(count + 1).toString().padLeft(6, '0')}',
      'comercio_id': user.comercioId,
      'unidade_id': unidadeId,
      'cliente_id': clienteId,
      'profissional_id': profissionalId,
      'status': 'aberta',
      'vencimento': vencimento?.toIso8601String(),
      'observacoes': observacoes,
      'criado_em': now.toIso8601String(),
      'atualizado_em': now.toIso8601String(),
    });
    return id;
  }

  Future<void> adicionarPorCodigo(
    String comandaId,
    String codigo, {
    double quantidade = 1,
  }) async {
    final user = _require(AcaoPermissao.realizarVenda);
    final db = await _databaseProvider();
    final products = await db.query(
      'estoque',
      where:
          "comercio_id = ? AND estoque_destino = 'loja' AND ativo = 1 AND (codigo_barras = ? OR codigo_interno = ? OR id = ?)",
      whereArgs: [user.comercioId, codigo, codigo, codigo],
      limit: 1,
    );
    if (products.isEmpty) throw StateError('Produto não encontrado.');
    await adicionarProduto(
      comandaId,
      products.single['id'] as String,
      quantidade: quantidade,
    );
  }

  Future<void> adicionarProduto(
    String comandaId,
    String produtoId, {
    double quantidade = 1,
    String? loteId,
    String? profissionalId,
  }) async {
    final user = _require(AcaoPermissao.realizarVenda);
    if (quantidade <= 0) throw StateError('Quantidade inválida.');
    final db = await _databaseProvider();
    await db.transaction((tx) async {
      await _open(tx, user.comercioId, comandaId);
      final products = await tx.query(
        'estoque',
        where:
            "id = ? AND comercio_id = ? AND estoque_destino = 'loja' AND ativo = 1",
        whereArgs: [produtoId, user.comercioId],
        limit: 1,
      );
      if (products.isEmpty) throw StateError('Produto indisponível.');
      final product = products.single;
      final price = (product['preco_venda'] as num?)?.toDouble() ?? 0;
      final existing = await tx.query(
        'comanda_loja_itens',
        where: 'comanda_id = ? AND comercio_id = ? AND produto_id = ?',
        whereArgs: [comandaId, user.comercioId, produtoId],
        limit: 1,
      );
      if (existing.isEmpty) {
        await tx.insert('comanda_loja_itens', {
          'id': IdGenerator.temporal(),
          'comanda_id': comandaId,
          'comercio_id': user.comercioId,
          'produto_id': produtoId,
          'lote_id': loteId,
          'codigo': product['codigo_barras'] ?? product['codigo_interno'],
          'nome': product['nome'],
          'quantidade': quantidade,
          'valor_unitario': price,
          'subtotal': price * quantidade,
          'profissional_id': profissionalId,
        });
      } else {
        final item = existing.single;
        final next = (item['quantidade'] as num).toDouble() + quantidade;
        await tx.update(
          'comanda_loja_itens',
          {'quantidade': next, 'subtotal': next * price},
          where: 'id = ?',
          whereArgs: [item['id']],
        );
      }
      await _recalculate(tx, user.comercioId, comandaId);
    });
  }

  Future<void> alterarQuantidade(
    String comandaId,
    String itemId,
    double quantidade,
  ) async {
    final user = _require(AcaoPermissao.realizarVenda);
    if (quantidade <= 0) return removerItem(comandaId, itemId);
    final db = await _databaseProvider();
    await db.transaction((tx) async {
      await _open(tx, user.comercioId, comandaId);
      final changed = await tx.rawUpdate(
        '''UPDATE comanda_loja_itens SET quantidade = ?,
           subtotal = (? * valor_unitario) - desconto
           WHERE id = ? AND comanda_id = ? AND comercio_id = ?''',
        [quantidade, quantidade, itemId, comandaId, user.comercioId],
      );
      if (changed == 0) throw StateError('Item não encontrado.');
      await _recalculate(tx, user.comercioId, comandaId);
    });
  }

  Future<void> removerItem(String comandaId, String itemId) async {
    final user = _require(AcaoPermissao.realizarVenda);
    final db = await _databaseProvider();
    await db.transaction((tx) async {
      await _open(tx, user.comercioId, comandaId);
      await tx.delete(
        'comanda_loja_itens',
        where: 'id = ? AND comanda_id = ? AND comercio_id = ?',
        whereArgs: [itemId, comandaId, user.comercioId],
      );
      await _recalculate(tx, user.comercioId, comandaId);
    });
  }

  Future<void> aplicarDesconto(String comandaId, double value) async {
    final user = _require(AcaoPermissao.aplicarDesconto);
    if (value < 0) throw StateError('Desconto inválido.');
    final db = await _databaseProvider();
    final rows = await _open(db, user.comercioId, comandaId);
    final subtotal = (rows.single['subtotal'] as num).toDouble();
    if (value > subtotal) throw StateError('Desconto maior que o subtotal.');
    await db.update(
      'comandas_loja',
      {
        'desconto': value,
        'total': subtotal - value,
        'atualizado_em': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [comandaId, user.comercioId],
    );
  }

  Future<void> finalizar(
    String comandaId, {
    double pagamentoInicial = 0,
    String formaPagamento = 'não informado',
    DateTime? vencimento,
    DateTime? dataPagamento,
  }) async {
    final user = _require(AcaoPermissao.realizarVenda);
    final db = await _databaseProvider();
    await db.transaction((tx) async {
      final command = (await _open(tx, user.comercioId, comandaId)).single;
      final items = await tx.query(
        'comanda_loja_itens',
        where: 'comanda_id = ? AND comercio_id = ?',
        whereArgs: [comandaId, user.comercioId],
      );
      if (items.isEmpty) throw StateError('A comanda está vazia.');
      final total = (command['total'] as num).toDouble();
      if (pagamentoInicial < 0 || pagamentoInicial > total) {
        throw StateError('Pagamento inválido.');
      }
      final saleId = IdGenerator.temporal();
      await tx.insert('pdv_vendas', {
        'id': saleId,
        'comercio_id': user.comercioId,
        'profissional_id': command['profissional_id'] ?? user.id,
        'cliente_id': command['cliente_id'],
        'valor_total': total,
        'data_venda': DateTime.now().toUtc().toIso8601String(),
        'status': 'concluida',
      });
      for (var index = 0; index < items.length; index++) {
        final item = items[index];
        final quantity = (item['quantidade'] as num).toDouble();
        final pieces = await tx.query(
          'pecas_unicas',
          where: 'id = ? AND comercio_id = ?',
          whereArgs: [item['produto_id'], user.comercioId],
          limit: 1,
        );
        final products = await tx.query(
          'estoque',
          columns: ['quantidade_atual'],
          where: 'id = ? AND comercio_id = ?',
          whereArgs: [item['produto_id'], user.comercioId],
          limit: 1,
        );
        if (pieces.isEmpty &&
            (products.isEmpty ||
                (products.single['quantidade_atual'] as num).toDouble() <
                    quantity)) {
          throw StateError('Estoque insuficiente para ${item['nome']}.');
        }
        await tx.insert('pdv_venda_itens', {
          'id': '${saleId}_$index',
          'pdv_venda_id': saleId,
          'produto_id': item['produto_id'],
          'quantidade': quantity,
          'valor_unitario': item['valor_unitario'],
        });
        if (pieces.isNotEmpty) {
          if (quantity != 1) {
            throw StateError('Peça única aceita quantidade 1.');
          }
          await _reconcileStockDelta(
            tx,
            user,
            {...command, 'venda_id': saleId},
            comandaId,
            item['produto_id'] as String,
            1,
          );
        } else {
          final before = (products.single['quantidade_atual'] as num)
              .toDouble();
          await tx.update(
            'estoque',
            {
              'quantidade_atual': before - quantity,
              'atualizado_em': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'id = ? AND comercio_id = ?',
            whereArgs: [item['produto_id'], user.comercioId],
          );
          await tx.insert('movimentacoes_estoque', {
            'id': IdGenerator.temporal(),
            'comercio_id': user.comercioId,
            'item_estoque_id': item['produto_id'],
            'tipo': 'venda',
            'quantidade': quantity,
            'quantidade_anterior': before,
            'quantidade_posterior': before - quantity,
            'data': DateTime.now().toUtc().toIso8601String(),
            'motivo': 'Baixa da comanda ${command['numero']}',
            'usuario_responsavel_id': user.id,
            'origem': 'comanda_loja',
            'referencia_id': comandaId,
          });
        }
        final commissionPercent = (item['comissao_percentual'] as num?)
            ?.toDouble();
        final professional =
            item['profissional_id'] ?? command['profissional_id'];
        if (commissionPercent != null &&
            commissionPercent > 0 &&
            professional != null) {
          await tx.insert('comanda_comissoes', {
            'id': IdGenerator.temporal(),
            'comercio_id': user.comercioId,
            'comanda_id': comandaId,
            'item_id': item['id'],
            'profissional_id': professional,
            'percentual': commissionPercent,
            'valor':
                (item['subtotal'] as num).toDouble() * commissionPercent / 100,
            'status': 'pendente',
            'criado_em': DateTime.now().toUtc().toIso8601String(),
          });
        }
      }
      if (pagamentoInicial > 0) {
        await _payment(
          tx,
          user,
          command,
          comandaId,
          pagamentoInicial,
          formaPagamento,
          dataPagamento: dataPagamento,
        );
      }
      final balance = total - pagamentoInicial;
      if (balance > 0) {
        final due =
            vencimento ??
            (command['vencimento'] == null
                ? null
                : DateTime.tryParse(command['vencimento'] as String));
        if (due == null) throw StateError('Informe o vencimento.');
        await tx.insert('contas_receber_loja', {
          'id': IdGenerator.temporal(),
          'comercio_id': user.comercioId,
          'unidade_id': command['unidade_id'],
          'cliente_id': command['cliente_id'],
          'comanda_id': comandaId,
          'profissional_id': command['profissional_id'] ?? user.id,
          'vencimento': due.toIso8601String(),
          'valor_total': total,
          'valor_recebido': pagamentoInicial,
          'status': pagamentoInicial > 0 ? 'parcialmente_paga' : 'pendente',
          'criado_em': DateTime.now().toUtc().toIso8601String(),
          'atualizado_em': DateTime.now().toUtc().toIso8601String(),
        });
      }
      await tx.update(
        'comandas_loja',
        {
          'status': balance <= 0
              ? 'paga'
              : pagamentoInicial > 0
              ? 'parcialmente_paga'
              : 'aguardando_pagamento',
          'valor_pago': pagamentoInicial,
          'venda_id': saleId,
          'finalizada_em': DateTime.now().toUtc().toIso8601String(),
          'atualizado_em': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ? AND comercio_id = ? AND status = ?',
        whereArgs: [comandaId, user.comercioId, 'aberta'],
      );
      await tx.insert('comanda_auditoria', {
        'id': IdGenerator.temporal(),
        'comercio_id': user.comercioId,
        'comanda_id': comandaId,
        'usuario_id': user.id,
        'acao': 'finalizacao',
        'detalhes': 'Venda $saleId; pagamento inicial $pagamentoInicial',
        'criado_em': DateTime.now().toUtc().toIso8601String(),
      });
    });
  }

  Future<void> registrarPagamento(
    String comandaId,
    double value,
    String method, {
    DateTime? dataPagamento,
  }) async {
    final user = _require(AcaoPermissao.realizarVenda);
    if (value <= 0) throw StateError('Pagamento inválido.');
    final db = await _databaseProvider();
    await db.transaction((tx) async {
      final rows = await tx.query(
        'comandas_loja',
        where:
            "id = ? AND comercio_id = ? AND status IN ('aguardando_pagamento','parcialmente_paga','vencida')",
        whereArgs: [comandaId, user.comercioId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Comanda sem saldo pendente.');
      final command = rows.single;
      final balance =
          (command['total'] as num).toDouble() -
          (command['valor_pago'] as num).toDouble();
      if (value > balance) throw StateError('Pagamento maior que o saldo.');
      await _payment(
        tx,
        user,
        command,
        comandaId,
        value,
        method,
        dataPagamento: dataPagamento,
      );
      final paid = (command['valor_pago'] as num).toDouble() + value;
      final status = (paid - (command['total'] as num).toDouble()).abs() < 0.01
          ? 'paga'
          : 'parcialmente_paga';
      await tx.update(
        'comandas_loja',
        {
          'valor_pago': paid,
          'status': status,
          'atualizado_em': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ? AND comercio_id = ?',
        whereArgs: [comandaId, user.comercioId],
      );
      await tx.update(
        'contas_receber_loja',
        {
          'valor_recebido': paid,
          'status': status,
          'atualizado_em': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'comanda_id = ? AND comercio_id = ?',
        whereArgs: [comandaId, user.comercioId],
      );
    });
  }

  Future<void> cancelar(String comandaId, String reason) async {
    final user = _require(AcaoPermissao.cancelarVenda);
    if (reason.trim().isEmpty) throw StateError('Informe o motivo.');
    final db = await _databaseProvider();
    final rows = await db.query(
      'comandas_loja',
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [comandaId, user.comercioId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Comanda não encontrada.');
    final command = rows.single;
    if (command['venda_id'] != null) {
      throw StateError('Comanda com venda deve ser estornada pelo histórico.');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((tx) async {
      await tx.update(
        'comandas_loja',
        {
          'status': 'cancelada',
          'cancelada_em': now,
          'motivo_cancelamento': reason.trim(),
          'atualizado_em': now,
        },
        where: 'id = ? AND comercio_id = ?',
        whereArgs: [comandaId, user.comercioId],
      );
      await tx.insert('comanda_auditoria', {
        'id': IdGenerator.temporal(),
        'comercio_id': user.comercioId,
        'comanda_id': comandaId,
        'usuario_id': user.id,
        'acao': 'cancelamento',
        'detalhes': reason.trim(),
        'criado_em': now,
      });
    });
  }

  Future<void> editar({
    required String comandaId,
    String? clienteId,
    String? profissionalId,
    DateTime? vencimento,
    String? observacoes,
  }) async {
    final user = _require(AcaoPermissao.realizarVenda);
    final db = await _databaseProvider();
    await db.transaction((tx) async {
      final rows = await tx.query(
        'comandas_loja',
        where:
            "id=? AND comercio_id=? AND status NOT IN ('cancelada','estornada')",
        whereArgs: [comandaId, user.comercioId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Comanda não pode ser editada.');
      final command = rows.single;
      await tx.update(
        'comandas_loja',
        {
          'cliente_id': ?clienteId,
          'profissional_id': ?profissionalId,
          if (vencimento != null)
            'vencimento': vencimento.toUtc().toIso8601String(),
          'observacoes': ?observacoes,
          'atualizado_em': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id=? AND comercio_id=?',
        whereArgs: [comandaId, user.comercioId],
      );
      if (clienteId != null && command['venda_id'] != null) {
        await tx.update(
          'pdv_vendas',
          {'cliente_id': clienteId},
          where: 'id=? AND comercio_id=?',
          whereArgs: [command['venda_id'], user.comercioId],
        );
        await tx.update(
          'contas_receber_loja',
          {'cliente_id': clienteId},
          where: 'comanda_id=? AND comercio_id=?',
          whereArgs: [comandaId, user.comercioId],
        );
      }
      await _audit(tx, user, comandaId, 'edicao_dados', 'Dados atualizados');
    });
  }

  Future<void> corrigirPagamento(
    String comandaId,
    String pagamentoId, {
    required String novaForma,
    required DateTime novaData,
    double? novoValor,
  }) async {
    final user = _require(AcaoPermissao.realizarVenda);
    if (novaForma.trim().isEmpty) throw StateError('Informe a forma.');
    final db = await _databaseProvider();
    await db.transaction((tx) async {
      final commands = await tx.query(
        'comandas_loja',
        where: 'id=? AND comercio_id=?',
        whereArgs: [comandaId, user.comercioId],
        limit: 1,
      );
      final payments = await tx.query(
        'comanda_loja_pagamentos',
        where: "id=? AND comanda_id=? AND comercio_id=? AND status='pago'",
        whereArgs: [pagamentoId, comandaId, user.comercioId],
        limit: 1,
      );
      if (commands.isEmpty || payments.isEmpty) {
        throw StateError('Pagamento não encontrado.');
      }
      final original = payments.single;
      final originalValue = (original['valor'] as num).toDouble();
      final correctedValue = novoValor ?? originalValue;
      final currentPaid = (commands.single['valor_pago'] as num).toDouble();
      final total = (commands.single['total'] as num).toDouble();
      final correctedPaid = currentPaid - originalValue + correctedValue;
      if (correctedValue <= 0 ||
          correctedPaid < 0 ||
          correctedPaid > total + 0.001) {
        throw StateError(
          'Valor corrigido incompatível com o saldo da comanda.',
        );
      }
      final now = DateTime.now().toUtc().toIso8601String();
      await tx.update(
        'comanda_loja_pagamentos',
        {'status': 'estornado'},
        where: 'id=?',
        whereArgs: [pagamentoId],
      );
      await tx.update(
        'movimentacoes_financeiras',
        {'status': 'estornado'},
        where: 'id=?',
        whereArgs: ['${pagamentoId}_finance'],
      );
      await tx.insert('movimentacoes_financeiras', {
        'id': '${pagamentoId}_correcao_estorno',
        'tipo': 'estorno',
        'descricao': 'Correção de pagamento da comanda',
        'valor': -originalValue,
        'forma_pagamento': original['forma'],
        'status': 'estornado',
        'data': now,
        'data_criacao': now,
        'categoria': 'venda de produto',
        'centro_resultado': 'loja',
        'entidade_origem': 'comanda',
        'entidade_origem_id': comandaId,
        'cliente_id': commands.single['cliente_id'],
        'profissional_id': commands.single['profissional_id'] ?? user.id,
        'usuario_responsavel_id': user.id,
        'observacoes': 'Correção auditável do pagamento $pagamentoId',
      });
      await _payment(
        tx,
        user,
        commands.single,
        comandaId,
        correctedValue,
        novaForma.trim(),
        dataPagamento: novaData,
      );
      final status = (total - correctedPaid).abs() < 0.01
          ? 'paga'
          : correctedPaid > 0
          ? 'parcialmente_paga'
          : 'aguardando_pagamento';
      await tx.update(
        'comandas_loja',
        {
          'valor_pago': correctedPaid,
          'status': status,
          'atualizado_em': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id=? AND comercio_id=?',
        whereArgs: [comandaId, user.comercioId],
      );
      await tx.update(
        'contas_receber_loja',
        {
          'valor_recebido': correctedPaid,
          'status': status == 'aguardando_pagamento' ? 'pendente' : status,
          'atualizado_em': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'comanda_id=? AND comercio_id=?',
        whereArgs: [comandaId, user.comercioId],
      );
      if (correctedPaid < total - 0.001) {
        final accounts = await tx.query(
          'contas_receber_loja',
          columns: ['id'],
          where: 'comanda_id=? AND comercio_id=?',
          whereArgs: [comandaId, user.comercioId],
          limit: 1,
        );
        if (accounts.isEmpty) {
          if (commands.single['vencimento'] == null) {
            throw StateError(
              'Informe um vencimento antes de reduzir o valor pago.',
            );
          }
          await tx.insert('contas_receber_loja', {
            'id': IdGenerator.temporal(),
            'comercio_id': user.comercioId,
            'unidade_id': commands.single['unidade_id'],
            'cliente_id': commands.single['cliente_id'],
            'comanda_id': comandaId,
            'profissional_id': commands.single['profissional_id'] ?? user.id,
            'vencimento': commands.single['vencimento'],
            'valor_total': total,
            'valor_recebido': correctedPaid,
            'status': correctedPaid > 0 ? 'parcialmente_paga' : 'pendente',
            'criado_em': now,
            'atualizado_em': now,
          });
        }
      }
      await _audit(
        tx,
        user,
        comandaId,
        'correcao_pagamento',
        'Pagamento $pagamentoId estornado e relançado',
      );
    });
  }

  /// Substitui a composição da mesma comanda e, se ela já estiver finalizada,
  /// movimenta apenas a diferença entre a composição anterior e a nova.
  Future<void> reconciliarItens(
    String comandaId,
    List<Map<String, Object?>> novosItens, {
    double? desconto,
    String? clienteId,
    DateTime? vencimento,
    String? observacoes,
  }) async {
    final user = _require(AcaoPermissao.realizarVenda);
    final db = await _databaseProvider();
    await db.transaction((tx) async {
      final rows = await tx.query(
        'comandas_loja',
        where:
            "id=? AND comercio_id=? AND status NOT IN ('cancelada','estornada')",
        whereArgs: [comandaId, user.comercioId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Comanda não pode ser editada.');
      var command = rows.single;
      if (clienteId != null || vencimento != null || observacoes != null) {
        await tx.update(
          'comandas_loja',
          {
            'cliente_id': ?clienteId,
            if (vencimento != null)
              'vencimento': vencimento.toUtc().toIso8601String(),
            'observacoes': ?observacoes,
            'atualizado_em': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'id=? AND comercio_id=?',
          whereArgs: [comandaId, user.comercioId],
        );
        command = {
          ...command,
          'cliente_id': ?clienteId,
          'vencimento': ?vencimento?.toUtc().toIso8601String(),
          'observacoes': ?observacoes,
        };
        if (clienteId != null && command['venda_id'] != null) {
          await tx.update(
            'pdv_vendas',
            {'cliente_id': clienteId},
            where: 'id=? AND comercio_id=?',
            whereArgs: [command['venda_id'], user.comercioId],
          );
          await tx.update(
            'contas_receber_loja',
            {'cliente_id': clienteId},
            where: 'comanda_id=? AND comercio_id=?',
            whereArgs: [comandaId, user.comercioId],
          );
        }
      }
      final saleId = command['venda_id'] as String?;
      final oldItems = await tx.query(
        'comanda_loja_itens',
        where: 'comanda_id=? AND comercio_id=?',
        whereArgs: [comandaId, user.comercioId],
      );
      final prepared = <Map<String, Object?>>[];
      for (final requested in novosItens) {
        final productId = requested['produto_id'] as String?;
        final quantity = (requested['quantidade'] as num? ?? 0).toDouble();
        if (productId == null || quantity <= 0) continue;
        final stock = await tx.query(
          'estoque',
          where:
              "id=? AND comercio_id=? AND ativo=1 AND estoque_destino='loja'",
          whereArgs: [productId, user.comercioId],
          limit: 1,
        );
        final pieces = await tx.query(
          'pecas_unicas',
          where: 'id=? AND comercio_id=?',
          whereArgs: [productId, user.comercioId],
          limit: 1,
        );
        if (stock.isEmpty && pieces.isEmpty) {
          throw StateError('Produto não encontrado.');
        }
        if (pieces.isNotEmpty && quantity != 1) {
          throw StateError('Peça única aceita quantidade 1.');
        }
        final source = stock.isNotEmpty ? stock.single : pieces.single;
        final unit =
            (requested['valor_unitario'] as num?)?.toDouble() ??
            (source[stock.isNotEmpty ? 'preco_venda' : 'preco'] as num?)
                ?.toDouble() ??
            0;
        final itemDiscount = (requested['desconto'] as num? ?? 0).toDouble();
        prepared.add({
          'id': requested['id'] ?? IdGenerator.temporal(),
          'comanda_id': comandaId,
          'comercio_id': user.comercioId,
          'produto_id': productId,
          'lote_id': requested['lote_id'] ?? source['lote_id'],
          'codigo':
              requested['codigo'] ??
              source['codigo_barras'] ??
              source['codigo_interno'] ??
              source['codigo_exclusivo'],
          'nome': requested['nome'] ?? source['nome'],
          'quantidade': quantity,
          'valor_unitario': unit,
          'desconto': itemDiscount,
          'subtotal': unit * quantity - itemDiscount,
          'profissional_id': requested['profissional_id'],
          'comissao_percentual': requested['comissao_percentual'],
        });
      }
      if (prepared.isEmpty) throw StateError('A comanda não pode ficar vazia.');
      final oldByProduct = <String, double>{};
      for (final item in oldItems) {
        final id = item['produto_id'] as String;
        oldByProduct[id] =
            (oldByProduct[id] ?? 0) + (item['quantidade'] as num).toDouble();
      }
      final newByProduct = <String, double>{};
      for (final item in prepared) {
        final id = item['produto_id'] as String;
        newByProduct[id] =
            (newByProduct[id] ?? 0) + (item['quantidade'] as num).toDouble();
      }
      if (saleId != null) {
        for (final productId in {...oldByProduct.keys, ...newByProduct.keys}) {
          final delta =
              (newByProduct[productId] ?? 0) - (oldByProduct[productId] ?? 0);
          if (delta.abs() < 0.0001) continue;
          await _reconcileStockDelta(
            tx,
            user,
            command,
            comandaId,
            productId,
            delta,
          );
        }
      }
      final subtotal = prepared.fold<double>(
        0,
        (sum, item) => sum + (item['subtotal'] as num).toDouble(),
      );
      final finalDiscount = desconto ?? (command['desconto'] as num).toDouble();
      final total = subtotal - finalDiscount;
      final paid = (command['valor_pago'] as num).toDouble();
      if (total < paid - 0.001) {
        throw StateError(
          'O novo total não pode ser menor que o valor já pago.',
        );
      }
      await tx.delete(
        'comanda_loja_itens',
        where: 'comanda_id=? AND comercio_id=?',
        whereArgs: [comandaId, user.comercioId],
      );
      for (final item in prepared) {
        await tx.insert('comanda_loja_itens', item);
      }
      if (saleId != null) {
        await tx.delete(
          'pdv_venda_itens',
          where: 'pdv_venda_id=?',
          whereArgs: [saleId],
        );
        for (var index = 0; index < prepared.length; index++) {
          final item = prepared[index];
          await tx.insert('pdv_venda_itens', {
            'id': '${saleId}_edit_$index',
            'pdv_venda_id': saleId,
            'produto_id': item['produto_id'],
            'quantidade': item['quantidade'],
            'valor_unitario': item['valor_unitario'],
          });
        }
        await tx.update(
          'pdv_vendas',
          {'valor_total': total},
          where: 'id=? AND comercio_id=?',
          whereArgs: [saleId, user.comercioId],
        );
        await tx.update(
          'contas_receber_loja',
          {
            'valor_total': total,
            'status': paid <= 0
                ? 'pendente'
                : (total - paid).abs() < 0.01
                ? 'paga'
                : 'parcialmente_paga',
            'atualizado_em': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'comanda_id=? AND comercio_id=?',
          whereArgs: [comandaId, user.comercioId],
        );
        if (total > paid + 0.001) {
          final accounts = await tx.query(
            'contas_receber_loja',
            columns: ['id'],
            where: 'comanda_id=? AND comercio_id=?',
            whereArgs: [comandaId, user.comercioId],
            limit: 1,
          );
          if (accounts.isEmpty) {
            if (command['vencimento'] == null) {
              throw StateError(
                'Informe o vencimento para o novo saldo em aberto.',
              );
            }
            final now = DateTime.now().toUtc().toIso8601String();
            await tx.insert('contas_receber_loja', {
              'id': IdGenerator.temporal(),
              'comercio_id': user.comercioId,
              'unidade_id': command['unidade_id'],
              'cliente_id': command['cliente_id'],
              'comanda_id': comandaId,
              'profissional_id': command['profissional_id'] ?? user.id,
              'vencimento': command['vencimento'],
              'valor_total': total,
              'valor_recebido': paid,
              'status': paid > 0 ? 'parcialmente_paga' : 'pendente',
              'criado_em': now,
              'atualizado_em': now,
            });
          }
        }
      }
      await tx.update(
        'comandas_loja',
        {
          'subtotal': subtotal,
          'desconto': finalDiscount,
          'total': total,
          if (saleId != null)
            'status': paid <= 0
                ? 'aguardando_pagamento'
                : (total - paid).abs() < 0.01
                ? 'paga'
                : 'parcialmente_paga',
          'atualizado_em': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id=? AND comercio_id=?',
        whereArgs: [comandaId, user.comercioId],
      );
      await _audit(
        tx,
        user,
        comandaId,
        'edicao_itens',
        'Composição reconciliada por diferença',
      );
    });
  }

  Future<String> resumoCompartilhavel(String comandaId) async {
    return PurchaseReceiptService.whatsappMessage(await comprovante(comandaId));
  }

  Future<PurchaseReceiptData> comprovante(String comandaId) async {
    final user = _require(AcaoPermissao.realizarVenda);
    final db = await _databaseProvider();
    final rows = await db.rawQuery(
      '''SELECT c.*, cl.nome cliente_nome, co.nome_exibicao comercio_nome,
      cp.forma forma_pagamento, cp.registrado_em data_pagamento
      FROM comandas_loja c JOIN clientes cl ON cl.id=c.cliente_id
      JOIN comercios co ON co.id=c.comercio_id
      LEFT JOIN comanda_loja_pagamentos cp ON cp.id=(
        SELECT p.id FROM comanda_loja_pagamentos p
        WHERE p.comanda_id=c.id ORDER BY p.registrado_em DESC LIMIT 1)
      WHERE c.id=? AND c.comercio_id=? LIMIT 1''',
      [comandaId, user.comercioId],
    );
    if (rows.isEmpty) throw StateError('Comanda não encontrada.');
    final command = rows.single;
    return PurchaseReceiptData(
      establishment: '${command['comercio_nome'] ?? user.nomeComercio}',
      client: '${command['cliente_nome']}',
      purchaseDate:
          DateTime.tryParse(
            '${command['finalizada_em'] ?? command['criado_em']}',
          ) ??
          DateTime.now(),
      paymentDate:
          DateTime.tryParse('${command['data_pagamento'] ?? ''}') ??
          DateTime.tryParse('${command['vencimento'] ?? ''}'),
      paymentMethod: '${command['forma_pagamento'] ?? 'Não informado'}',
      notes: command['observacoes'] as String?,
      items: await itens(comandaId),
    );
  }

  Future<void> estornar(String comandaId, String motivo) async {
    final user = _require(AcaoPermissao.cancelarVenda);
    if (motivo.trim().isEmpty) throw StateError('Informe o motivo.');
    final db = await _databaseProvider();
    await db.transaction((tx) async {
      final commands = await tx.query(
        'comandas_loja',
        where:
            "id=? AND comercio_id=? AND status IN ('paga','parcialmente_paga','aguardando_pagamento','vencida')",
        whereArgs: [comandaId, user.comercioId],
        limit: 1,
      );
      if (commands.isEmpty) throw StateError('Comanda não pode ser estornada.');
      final command = commands.single;
      final saleId = command['venda_id'] as String?;
      if (saleId == null) throw StateError('Venda não encontrada.');
      final sold = await tx.query(
        'pdv_venda_itens',
        where: 'pdv_venda_id=?',
        whereArgs: [saleId],
      );
      final now = DateTime.now().toUtc().toIso8601String();
      for (final item in sold) {
        final pieces = await tx.query(
          'pecas_unicas',
          where: 'id=? AND comercio_id=?',
          whereArgs: [item['produto_id'], user.comercioId],
          limit: 1,
        );
        if (pieces.isNotEmpty) {
          final piece = pieces.single;
          await tx.update(
            'pecas_unicas',
            {
              'status': 'disponivel',
              'cliente_id': null,
              'profissional_vendedor_id': null,
              'data_venda': null,
              'comissao': null,
            },
            where: 'id=? AND comercio_id=?',
            whereArgs: [item['produto_id'], user.comercioId],
          );
          await tx.insert('consignacao_eventos', {
            'id': IdGenerator.temporal(),
            'comercio_id': user.comercioId,
            'consignacao_id': piece['lote_id'],
            'peca_id': item['produto_id'],
            'tipo': 'cancelamento_venda',
            'quantidade': 1,
            'valor': item['valor_unitario'],
            'observacoes': motivo.trim(),
            'venda_id': saleId,
            'criado_em': now,
          });
          await tx.rawUpdate(
            '''UPDATE consignacoes SET
              quantidade_vendida=MAX(0,COALESCE(quantidade_vendida,0)-1),
              quantidade_disponivel=COALESCE(quantidade_disponivel,0)+1,
              valor_vendido=MAX(0,COALESCE(valor_vendido,0)-?)
              WHERE id=? AND comercio_id=?''',
            [item['valor_unitario'], piece['lote_id'], user.comercioId],
          );
          continue;
        }
        final products = await tx.query(
          'estoque',
          columns: ['quantidade_atual'],
          where: 'id=? AND comercio_id=?',
          whereArgs: [item['produto_id'], user.comercioId],
          limit: 1,
        );
        if (products.isEmpty) continue;
        final before = (products.single['quantidade_atual'] as num).toDouble();
        final quantity = (item['quantidade'] as num).toDouble();
        await tx.update(
          'estoque',
          {'quantidade_atual': before + quantity, 'atualizado_em': now},
          where: 'id=? AND comercio_id=?',
          whereArgs: [item['produto_id'], user.comercioId],
        );
        await tx.insert('movimentacoes_estoque', {
          'id': IdGenerator.temporal(),
          'comercio_id': user.comercioId,
          'item_estoque_id': item['produto_id'],
          'tipo': 'estorno_venda',
          'quantidade': quantity,
          'quantidade_anterior': before,
          'quantidade_posterior': before + quantity,
          'data': now,
          'motivo': motivo.trim(),
          'usuario_responsavel_id': user.id,
          'origem': 'comanda_loja',
          'referencia_id': comandaId,
        });
      }
      await tx.update(
        'pdv_vendas',
        {'status': 'estornada'},
        where: 'id=?',
        whereArgs: [saleId],
      );
      await tx.update(
        'comandas_loja',
        {
          'status': 'estornada',
          'motivo_cancelamento': motivo.trim(),
          'cancelada_em': now,
          'atualizado_em': now,
        },
        where: 'id=?',
        whereArgs: [comandaId],
      );
      await tx.update(
        'contas_receber_loja',
        {'status': 'estornada', 'atualizado_em': now},
        where: 'comanda_id=? AND comercio_id=?',
        whereArgs: [comandaId, user.comercioId],
      );
      await tx.update(
        'comanda_comissoes',
        {'status': 'estornada'},
        where: 'comanda_id=? AND comercio_id=?',
        whereArgs: [comandaId, user.comercioId],
      );
      await tx.insert('comanda_auditoria', {
        'id': IdGenerator.temporal(),
        'comercio_id': user.comercioId,
        'comanda_id': comandaId,
        'usuario_id': user.id,
        'acao': 'estorno',
        'detalhes': motivo.trim(),
        'criado_em': now,
      });
    });
  }

  Future<List<Map<String, Object?>>> clientesDisponiveis() async {
    final user = _require(AcaoPermissao.realizarVenda);
    final db = await _databaseProvider();
    return db.query(
      'clientes',
      columns: ['id', 'nome', 'whatsapp'],
      where: 'comercio_id=? AND ativo=1',
      whereArgs: [user.comercioId],
      orderBy: 'nome COLLATE NOCASE',
    );
  }

  Future<List<Map<String, Object?>>> produtosDisponiveis([
    String busca = '',
  ]) async {
    final user = _require(AcaoPermissao.realizarVenda);
    final db = await _databaseProvider();
    final query = busca.trim();
    final like = '%$query%';
    return db.rawQuery(
      '''SELECT id,nome,codigo_barras,codigo_interno,preco_venda,
          quantidade_atual,'estoque' origem_produto
        FROM estoque
        WHERE comercio_id=? AND ativo=1 AND estoque_destino='loja'
          AND (?='' OR nome LIKE ? OR codigo_barras LIKE ? OR codigo_interno LIKE ?)
        UNION ALL
        SELECT id,nome,codigo_exclusivo codigo_barras,NULL codigo_interno,
          preco preco_venda,1 quantidade_atual,'peca_unica' origem_produto
        FROM pecas_unicas
        WHERE comercio_id=? AND status='disponivel'
          AND (?='' OR nome LIKE ? OR codigo_exclusivo LIKE ?)
        ORDER BY nome COLLATE NOCASE LIMIT 100''',
      [
        user.comercioId,
        query,
        like,
        like,
        like,
        user.comercioId,
        query,
        like,
        like,
      ],
    );
  }

  Future<void> definirComissao(
    String comandaId,
    String itemId, {
    required String profissionalId,
    required double percentual,
  }) async {
    final user = _require(AcaoPermissao.realizarVenda);
    if (percentual < 0 || percentual > 100) {
      throw StateError('Comissão inválida.');
    }
    final db = await _databaseProvider();
    await _open(db, user.comercioId, comandaId);
    final changed = await db.update(
      'comanda_loja_itens',
      {'profissional_id': profissionalId, 'comissao_percentual': percentual},
      where: 'id=? AND comanda_id=? AND comercio_id=?',
      whereArgs: [itemId, comandaId, user.comercioId],
    );
    if (changed == 0) throw StateError('Item não encontrado.');
  }

  Future<List<Map<String, Object?>>> listar({String? status}) async {
    final user = _require(AcaoPermissao.realizarVenda);
    final db = await _databaseProvider();
    return db.rawQuery(
      '''SELECT c.*, cl.nome cliente_nome
         FROM comandas_loja c JOIN clientes cl ON cl.id = c.cliente_id
         WHERE c.comercio_id = ? ${status == null ? '' : 'AND c.status = ?'}
         ORDER BY c.criado_em DESC''',
      [user.comercioId, ?status],
    );
  }

  Future<List<Map<String, Object?>>> itens(String comandaId) async {
    final user = _require(AcaoPermissao.realizarVenda);
    final db = await _databaseProvider();
    return db.query(
      'comanda_loja_itens',
      where: 'comanda_id = ? AND comercio_id = ?',
      whereArgs: [comandaId, user.comercioId],
      orderBy: 'nome COLLATE NOCASE',
    );
  }

  Future<List<Map<String, Object?>>> _open(
    DatabaseExecutor db,
    String businessId,
    String commandId,
  ) async {
    final rows = await db.query(
      'comandas_loja',
      where: 'id = ? AND comercio_id = ? AND status = ?',
      whereArgs: [commandId, businessId, 'aberta'],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Comanda não está aberta.');
    return rows;
  }

  Future<void> _recalculate(
    DatabaseExecutor db,
    String businessId,
    String commandId,
  ) async {
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(subtotal),0) total FROM comanda_loja_itens WHERE comanda_id = ? AND comercio_id = ?',
      [commandId, businessId],
    );
    final subtotal = (result.single['total'] as num).toDouble();
    final command = await db.query(
      'comandas_loja',
      columns: ['desconto'],
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [commandId, businessId],
      limit: 1,
    );
    final discount = (command.single['desconto'] as num).toDouble();
    await db.update(
      'comandas_loja',
      {
        'subtotal': subtotal,
        'total': subtotal - discount,
        'atualizado_em': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [commandId, businessId],
    );
  }

  Future<void> _reconcileStockDelta(
    DatabaseExecutor db,
    UsuarioAcesso user,
    Map<String, Object?> command,
    String commandId,
    String productId,
    double delta,
  ) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final pieces = await db.query(
      'pecas_unicas',
      where: 'id=? AND comercio_id=?',
      whereArgs: [productId, user.comercioId],
      limit: 1,
    );
    if (pieces.isNotEmpty) {
      if (delta.abs() != 1) {
        throw StateError('Peça única aceita somente uma ocorrência.');
      }
      final piece = pieces.single;
      if (delta > 0) {
        final changed = await db.update(
          'pecas_unicas',
          {
            'status': 'vendida',
            'cliente_id': command['cliente_id'],
            'profissional_vendedor_id': command['profissional_id'] ?? user.id,
            'data_venda': now,
          },
          where: "id=? AND comercio_id=? AND status='disponivel'",
          whereArgs: [productId, user.comercioId],
        );
        if (changed == 0) throw StateError('Peça única indisponível.');
      } else {
        await db.update(
          'pecas_unicas',
          {
            'status': 'disponivel',
            'cliente_id': null,
            'profissional_vendedor_id': null,
            'data_venda': null,
            'comissao': null,
          },
          where: "id=? AND comercio_id=? AND status='vendida'",
          whereArgs: [productId, user.comercioId],
        );
      }
      await db.insert('consignacao_eventos', {
        'id': IdGenerator.temporal(),
        'comercio_id': user.comercioId,
        'consignacao_id': piece['lote_id'],
        'peca_id': productId,
        'tipo': delta > 0 ? 'ajuste_edicao_venda' : 'reversao_edicao_venda',
        'quantidade': 1,
        'valor': piece['preco'],
        'cliente_id': delta > 0 ? command['cliente_id'] : null,
        'profissional_id': delta > 0
            ? command['profissional_id'] ?? user.id
            : null,
        'observacoes': 'Reconciliação da comanda $commandId',
        'venda_id': command['venda_id'],
        'criado_em': now,
      });
      await db.rawUpdate(
        '''UPDATE consignacoes SET
          quantidade_vendida=MAX(0,COALESCE(quantidade_vendida,0)+?),
          quantidade_disponivel=MAX(0,COALESCE(quantidade_disponivel,0)-?),
          valor_vendido=MAX(0,COALESCE(valor_vendido,0)+?)
          WHERE id=? AND comercio_id=?''',
        [
          delta,
          delta,
          delta * (piece['preco'] as num).toDouble(),
          piece['lote_id'],
          user.comercioId,
        ],
      );
      return;
    }
    final products = await db.query(
      'estoque',
      columns: ['quantidade_atual'],
      where: 'id=? AND comercio_id=?',
      whereArgs: [productId, user.comercioId],
      limit: 1,
    );
    if (products.isEmpty) throw StateError('Produto não encontrado.');
    final before = (products.single['quantidade_atual'] as num).toDouble();
    final after = before - delta;
    if (after < -0.0001) throw StateError('Estoque insuficiente.');
    await db.update(
      'estoque',
      {'quantidade_atual': after, 'atualizado_em': now},
      where: 'id=? AND comercio_id=?',
      whereArgs: [productId, user.comercioId],
    );
    await db.insert('movimentacoes_estoque', {
      'id': IdGenerator.temporal(),
      'comercio_id': user.comercioId,
      'item_estoque_id': productId,
      'tipo': delta > 0 ? 'venda' : 'estorno_venda',
      'quantidade': delta.abs(),
      'quantidade_anterior': before,
      'quantidade_posterior': after,
      'data': now,
      'motivo': 'Reconciliação da comanda ${command['numero']}',
      'usuario_responsavel_id': user.id,
      'origem': 'edicao_comanda',
      'referencia_id': commandId,
    });
  }

  Future<void> _audit(
    DatabaseExecutor db,
    UsuarioAcesso user,
    String commandId,
    String action,
    String details,
  ) => db.insert('comanda_auditoria', {
    'id': IdGenerator.temporal(),
    'comercio_id': user.comercioId,
    'comanda_id': commandId,
    'usuario_id': user.id,
    'acao': action,
    'detalhes': details,
    'criado_em': DateTime.now().toUtc().toIso8601String(),
  });

  Future<void> _payment(
    DatabaseExecutor db,
    UsuarioAcesso user,
    Map<String, Object?> command,
    String commandId,
    double value,
    String method, {
    DateTime? dataPagamento,
  }) async {
    final now = (dataPagamento ?? DateTime.now()).toUtc().toIso8601String();
    final id = IdGenerator.temporal();
    await db.insert('comanda_loja_pagamentos', {
      'id': id,
      'comanda_id': commandId,
      'comercio_id': user.comercioId,
      'forma': method,
      'valor': value,
      'status': 'pago',
      'registrado_em': now,
    });
    await db.insert('movimentacoes_financeiras', {
      'id': '${id}_finance',
      'tipo': 'receita',
      'descricao': 'Pagamento da comanda ${command['numero']}',
      'valor': value,
      'forma_pagamento': method,
      'status': 'pago',
      'data': now,
      'data_criacao': now,
      'categoria': 'venda de produto',
      'centro_resultado': 'loja',
      'entidade_origem': 'comanda',
      'entidade_origem_id': commandId,
      'cliente_id': command['cliente_id'],
      'profissional_id': command['profissional_id'] ?? user.id,
      'usuario_responsavel_id': user.id,
    });
  }
}
