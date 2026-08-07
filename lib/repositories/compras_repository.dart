import 'package:sqflite/sqflite.dart';

import '../core/utils/id_generator.dart';
import '../database/database_service.dart';
import '../models/domain/acesso.dart';
import '../models/domain/loja.dart';
import '../services/session_controller.dart';

class ItemOrdemEntrada {
  final ProdutoLoja produto;
  final double quantidade;
  final double valorUnitario;
  const ItemOrdemEntrada(this.produto, this.quantidade, this.valorUnitario);
}

class ComprasRepository {
  final Future<Database> Function() _databaseProvider;
  ComprasRepository({Future<Database> Function()? databaseProvider})
    : _databaseProvider =
          databaseProvider ?? (() => DatabaseService.instance.database);

  UsuarioAcesso get _usuario {
    final u = SessionController.instance.usuario;
    if (u == null || !u.pode(ModuloPermissao.lojaSalao)) {
      throw StateError('Acesso à Loja do Salão não autorizado.');
    }
    return u;
  }

  UsuarioAcesso _exigir(AcaoPermissao acao) {
    final usuario = _usuario;
    if (!usuario.podeAcao(acao)) {
      throw StateError(
        'Você não possui permissão para ${acao.nome.toLowerCase()}.',
      );
    }
    return usuario;
  }

  Future<String> criarOrdem({
    required List<ItemOrdemEntrada> itens,
    String? fornecedorId,
    double frete = 0,
    double desconto = 0,
    String? endereco,
    String? observacoes,
  }) async {
    final u = _exigir(AcaoPermissao.criarPedido);
    if (itens.isEmpty) throw StateError('Adicione ao menos um produto.');
    final subtotal = itens.fold<double>(
      0,
      (total, item) => total + item.quantidade * item.valorUnitario,
    );
    final total = subtotal + frete - desconto;
    if (total < 0) throw StateError('Total da ordem inválido.');
    final id = IdGenerator.temporal();
    final agora = DateTime.now();
    final numero = 'OC${agora.millisecondsSinceEpoch}';
    final db = await _databaseProvider();
    await db.transaction((txn) async {
      await txn.insert('ordens_compra', {
        'id': id,
        'numero': numero,
        'comercio_id': u.comercioId,
        'fornecedor_id': fornecedorId,
        'usuario_id': u.id,
        'frete': frete,
        'desconto': desconto,
        'total': total,
        'endereco': endereco,
        'observacoes': observacoes,
        'status': 'aguardando_aprovacao',
        'criada_em': agora.toIso8601String(),
        'atualizado_em': agora.toIso8601String(),
      });
      for (var i = 0; i < itens.length; i++) {
        final item = itens[i];
        if (item.produto.comercioId != u.comercioId || item.quantidade <= 0) {
          throw StateError('Item inválido para este comércio.');
        }
        await txn.insert('ordem_compra_itens', {
          'id': '${id}_$i',
          'ordem_id': id,
          'comercio_id': u.comercioId,
          'produto_id': item.produto.id,
          'quantidade': item.quantidade,
          'valor_unitario': item.valorUnitario,
          'total': item.quantidade * item.valorUnitario,
        });
      }
      await _historico(txn, id, 'aguardando_aprovacao', observacoes);
      await _atualizarReposicoesDaOrdem(txn, id, 'aguardando_aprovacao');
    });
    return id;
  }

  Future<void> aprovar(String ordemId) async {
    final u = _exigir(AcaoPermissao.aprovarPedido);
    final db = await _databaseProvider();
    await db.transaction((txn) async {
      final alterados = await txn.update(
        'ordens_compra',
        {
          'status': 'aprovado',
          'aprovado_por_id': u.id,
          'atualizado_em': DateTime.now().toIso8601String(),
        },
        where: 'id = ? AND comercio_id = ? AND status = ?',
        whereArgs: [ordemId, u.comercioId, 'aguardando_aprovacao'],
      );
      if (alterados == 0) {
        throw StateError('Ordem não está aguardando aprovação.');
      }
      await _historico(txn, ordemId, 'aprovado', 'Ordem aprovada');
      await _atualizarReposicoesDaOrdem(txn, ordemId, 'aprovado');
    });
  }

  Future<void> atualizarStatus(String ordemId, String status) async {
    const permitidos = {
      'enviado',
      'confirmado',
      'em_separacao',
      'em_transporte',
      'cancelado',
    };
    if (!permitidos.contains(status)) throw StateError('Status inválido.');
    final u = _usuario;
    final db = await _databaseProvider();
    await db.transaction((txn) async {
      await txn.update(
        'ordens_compra',
        {'status': status, 'atualizado_em': DateTime.now().toIso8601String()},
        where: "id = ? AND comercio_id = ?",
        whereArgs: [ordemId, u.comercioId],
      );
      await _historico(txn, ordemId, status, null);
      await _atualizarReposicoesDaOrdem(txn, ordemId, status);
    });
  }

  Future<void> receber(
    String ordemId,
    Map<String, double> quantidades, {
    String? observacao,
  }) async {
    final u = _exigir(AcaoPermissao.receberPedido);
    final db = await _databaseProvider();
    await db.transaction((txn) async {
      final ordem = await txn.query(
        'ordens_compra',
        where:
            "id = ? AND comercio_id = ? AND status NOT IN ('cancelado','recebido')",
        whereArgs: [ordemId, u.comercioId],
        limit: 1,
      );
      if (ordem.isEmpty) {
        throw StateError('Ordem indisponível para recebimento.');
      }
      final itens = await txn.query(
        'ordem_compra_itens',
        where: 'ordem_id = ? AND comercio_id = ?',
        whereArgs: [ordemId, u.comercioId],
      );
      for (final item in itens) {
        final itemId = item['id'] as String;
        final recebidaAgora = quantidades[itemId] ?? 0;
        if (recebidaAgora < 0) {
          throw StateError('Quantidade recebida inválida.');
        }
        final pedida = (item['quantidade'] as num).toDouble();
        final recebida = (item['quantidade_recebida'] as num).toDouble();
        if (recebida + recebidaAgora > pedida) {
          throw StateError('Recebimento excede a quantidade pedida.');
        }
        if (recebidaAgora > 0) {
          await txn.update(
            'ordem_compra_itens',
            {'quantidade_recebida': recebida + recebidaAgora},
            where: 'id = ?',
            whereArgs: [itemId],
          );
          await _entradaEstoque(
            txn,
            item['produto_id'] as String,
            recebidaAgora,
            ordemId,
            observacao,
          );
        }
      }
      final pendentes =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              '''SELECT COUNT(*)
        FROM ordem_compra_itens WHERE ordem_id = ? AND quantidade_recebida < quantidade''',
              [ordemId],
            ),
          ) ??
          0;
      final status = pendentes == 0 ? 'recebido' : 'recebido_parcialmente';
      await txn.update(
        'ordens_compra',
        {'status': status, 'atualizado_em': DateTime.now().toIso8601String()},
        where: "id = ? AND comercio_id = ?",
        whereArgs: [ordemId, u.comercioId],
      );
      await _historico(txn, ordemId, status, observacao);
      await _atualizarReposicoesDaOrdem(txn, ordemId, status);
    });
  }

  Future<void> _entradaEstoque(
    Transaction txn,
    String produtoId,
    double quantidade,
    String ordemId,
    String? observacao,
  ) async {
    final u = _usuario;
    final produto = await txn.query(
      'estoque',
      where: "id = ? AND comercio_id = ? AND estoque_destino = 'loja'",
      whereArgs: [produtoId, u.comercioId],
      limit: 1,
    );
    if (produto.isEmpty) throw StateError('Produto recebido não encontrado.');

    final saldoQuery = await txn.query(
      'estoque_saldos',
      where: "estoque_id = ? AND business_id = ? AND finalidade = 'venda'",
      whereArgs: [produtoId, u.comercioId],
      limit: 1,
    );

    final anterior = saldoQuery.isNotEmpty
        ? (saldoQuery.first['quantidade_atual'] as num).toDouble()
        : (produto.first['quantidade_atual'] as num).toDouble();

    final posterior = anterior + quantidade;

    if (saldoQuery.isNotEmpty) {
      await txn.update(
        'estoque_saldos',
        {
          'quantidade_atual': posterior,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: "estoque_id = ? AND business_id = ? AND finalidade = 'venda'",
        whereArgs: [produtoId, u.comercioId],
      );
    }

    await txn.update(
      'estoque',
      {
        'quantidade_atual': posterior,
        'atualizado_em': DateTime.now().toIso8601String(),
      },
      where: "id = ? AND comercio_id = ? AND estoque_destino = 'loja'",
      whereArgs: [produtoId, u.comercioId],
    );
    await txn.insert('movimentacoes_estoque', {
      'id': IdGenerator.temporal(),
      'comercio_id': u.comercioId,
      'item_estoque_id': produtoId,
      'tipo': TipoMovimentoLoja.entradaRecebimento.chave,
      'quantidade': quantidade,
      'quantidade_anterior': anterior,
      'quantidade_posterior': posterior,
      'data': DateTime.now().toIso8601String(),
      'motivo': observacao,
      'usuario_responsavel_id': u.id,
      'origem': 'ordem_compra',
      'referencia_id': ordemId,
    });
  }

  Future<void> _atualizarReposicoesDaOrdem(
    Transaction txn,
    String ordemId,
    String status,
  ) async {
    await txn.rawUpdate(
      '''UPDATE reposicoes
      SET status = ?, atualizado_em = ?
      WHERE comercio_id = ?
        AND produto_id IN (SELECT produto_id FROM ordem_compra_itens WHERE ordem_id = ?)
        AND status NOT IN ('cancelado', 'recebido')''',
      [status, DateTime.now().toIso8601String(), _usuario.comercioId, ordemId],
    );
  }

  Future<void> _historico(
    Transaction txn,
    String ordemId,
    String status,
    String? observacao,
  ) => txn.insert('ordem_compra_historico', {
    'id': IdGenerator.temporal(),
    'ordem_id': ordemId,
    'comercio_id': _usuario.comercioId,
    'status': status,
    'usuario_id': _usuario.id,
    'observacao': observacao,
    'data': DateTime.now().toIso8601String(),
  });

  Future<List<Map<String, Object?>>> listarOrdens() async {
    final u = _usuario;
    final db = await _databaseProvider();
    return db.rawQuery(
      '''SELECT o.*, f.nome fornecedor_nome
      FROM ordens_compra o LEFT JOIN fornecedores f ON f.id = o.fornecedor_id
      WHERE o.comercio_id = ? ORDER BY o.criada_em DESC''',
      [u.comercioId],
    );
  }

  Future<List<Map<String, Object?>>> itensOrdem(String ordemId) async {
    final u = _usuario;
    final db = await _databaseProvider();
    return db.rawQuery(
      '''SELECT i.*, e.nome produto_nome
      FROM ordem_compra_itens i JOIN estoque e ON e.id = i.produto_id
      WHERE i.ordem_id = ? AND i.comercio_id = ?''',
      [ordemId, u.comercioId],
    );
  }
}
