import 'package:sqflite/sqflite.dart';

import '../core/utils/id_generator.dart';
import '../database/database_service.dart';
import '../models/domain/acesso.dart';
import '../models/domain/loja.dart';
import '../services/session_controller.dart';

class ConsignacaoRepository {
  final Future<Database> Function() _databaseProvider;
  ConsignacaoRepository({Future<Database> Function()? databaseProvider})
    : _databaseProvider =
          databaseProvider ?? (() => DatabaseService.instance.database);

  UsuarioAcesso get _usuario {
    final u = SessionController.instance.usuario;
    if (u == null ||
        !u.pode(ModuloPermissao.lojaSalao) ||
        !u.podeAcao(AcaoPermissao.acessarConsignacao)) {
      throw StateError('Acesso à consignação não autorizado.');
    }
    return u;
  }

  Future<String> receber({
    required String fornecedorId,
    required String produtoId,
    required double quantidade,
    required double repasse,
    required double precoVenda,
    required double percentualSalao,
    String? lote,
    DateTime? fechamentoPrevisto,
  }) async {
    final u = _usuario;
    if (quantidade <= 0 || repasse < 0 || precoVenda < 0) {
      throw StateError('Dados da consignação inválidos.');
    }
    final db = await _databaseProvider();
    final id = IdGenerator.temporal();
    await db.transaction((txn) async {
      final agora = DateTime.now();
      await txn.insert('consignacoes', {
        'id': id,
        'comercio_id': u.comercioId,
        'fornecedor_id': fornecedorId,
        'lote_colecao': lote,
        'recebida_em': agora.toIso8601String(),
        'fechamento_previsto': fechamentoPrevisto?.toIso8601String(),
        'status': 'aberta',
        'criado_em': agora.toIso8601String(),
      });
      await txn.insert('consignacao_itens', {
        'id': '${id}_0',
        'consignacao_id': id,
        'comercio_id': u.comercioId,
        'produto_id': produtoId,
        'quantidade_recebida': quantidade,
        'valor_repasse': repasse,
        'preco_venda': precoVenda,
        'percentual_salao': percentualSalao,
      });
      final produto = await txn.query(
        'estoque',
        where: "id = ? AND comercio_id = ? AND estoque_destino = 'loja'",
        whereArgs: [produtoId, u.comercioId],
        limit: 1,
      );
      if (produto.isEmpty) throw StateError('Produto não encontrado.');

      final saldoQuery = await txn.query(
        'estoque_saldos',
        where: "estoque_id = ? AND business_id = ? AND finalidade = 'venda'",
        whereArgs: [produtoId, u.comercioId],
        limit: 1,
      );

      final anterior = saldoQuery.isNotEmpty
          ? (saldoQuery.first['quantidade_atual'] as num).toDouble()
          : (produto.first['quantidade_atual'] as num).toDouble();

      if (saldoQuery.isNotEmpty) {
        await txn.update(
          'estoque_saldos',
          {
            'quantidade_atual': anterior + quantidade,
            'updated_at': agora.toUtc().toIso8601String(),
          },
          where: "estoque_id = ? AND business_id = ? AND finalidade = 'venda'",
          whereArgs: [produtoId, u.comercioId],
        );
      }

      await txn.update(
        'estoque',
        {
          'quantidade_atual': anterior + quantidade,
          'modalidade': 'consignado',
          'preco_venda': precoVenda,
          'fornecedor_principal_id': fornecedorId,
          'atualizado_em': agora.toIso8601String(),
        },
        where: "id = ? AND comercio_id = ? AND estoque_destino = 'loja'",
        whereArgs: [produtoId, u.comercioId],
      );
      await txn.insert('movimentacoes_estoque', {
        'id': IdGenerator.temporal(),
        'comercio_id': u.comercioId,
        'item_estoque_id': produtoId,
        'tipo': TipoMovimentoLoja.recebimentoConsignado.chave,
        'quantidade': quantidade,
        'quantidade_anterior': anterior,
        'quantidade_posterior': anterior + quantidade,
        'data': agora.toIso8601String(),
        'motivo': 'Recebimento consignado',
        'usuario_responsavel_id': u.id,
        'origem': 'consignacao',
        'referencia_id': id,
      });
    });
    return id;
  }

  Future<ResumoConsignacao> resumo(String consignacaoId) async {
    final u = _usuario;
    final db = await _databaseProvider();
    final itens = await db.query(
      'consignacao_itens',
      where: 'consignacao_id = ? AND comercio_id = ?',
      whereArgs: [consignacaoId, u.comercioId],
    );
    var recebidos = 0.0, vendidos = 0.0, devolvidos = 0.0;
    var faturamento = 0.0, fornecedor = 0.0;
    for (final i in itens) {
      final r = (i['quantidade_recebida'] as num).toDouble();
      final v = (i['quantidade_vendida'] as num).toDouble();
      final d = (i['quantidade_devolvida'] as num).toDouble();
      recebidos += r;
      vendidos += v;
      devolvidos += d;
      faturamento += v * (i['preco_venda'] as num).toDouble();
      fornecedor += v * (i['valor_repasse'] as num).toDouble();
    }
    return ResumoConsignacao(
      recebidos: recebidos,
      vendidos: vendidos,
      devolvidos: devolvidos,
      disponiveis: recebidos - vendidos - devolvidos,
      faturamento: faturamento,
      valorFornecedor: fornecedor,
    );
  }

  Future<void> fechar(String consignacaoId) async {
    final u = _usuario;
    final db = await _databaseProvider();
    await db.transaction((txn) async {
      final consignacao = await txn.query(
        'consignacoes',
        columns: ['id'],
        where: 'id = ? AND comercio_id = ? AND status = ?',
        whereArgs: [consignacaoId, u.comercioId, 'aberta'],
        limit: 1,
      );
      if (consignacao.isEmpty) {
        throw StateError('Consignação já fechada ou inexistente.');
      }
      final itens = await txn.query(
        'consignacao_itens',
        where: 'consignacao_id = ? AND comercio_id = ?',
        whereArgs: [consignacaoId, u.comercioId],
      );
      for (final item in itens) {
        final recebida = (item['quantidade_recebida'] as num).toDouble();
        final vendida = (item['quantidade_vendida'] as num).toDouble();
        final devolvida = (item['quantidade_devolvida'] as num).toDouble();
        final restante = recebida - vendida - devolvida;
        if (restante <= 0) continue;
        final produtoId = item['produto_id'] as String;
        final produtos = await txn.query(
          'estoque',
          where: "id = ? AND comercio_id = ? AND estoque_destino = 'loja'",
          whereArgs: [produtoId, u.comercioId],
          limit: 1,
        );
        if (produtos.isEmpty) {
          throw StateError('Produto consignado não encontrado.');
        }

        final saldoQuery = await txn.query(
          'estoque_saldos',
          where: "estoque_id = ? AND business_id = ? AND finalidade = 'venda'",
          whereArgs: [produtoId, u.comercioId],
          limit: 1,
        );

        final anterior = saldoQuery.isNotEmpty
            ? (saldoQuery.first['quantidade_atual'] as num).toDouble()
            : (produtos.first['quantidade_atual'] as num).toDouble();

        if (anterior < restante) {
          throw StateError(
            'Estoque consignado divergente. Ajuste o produto antes de fechar.',
          );
        }
        final posterior = anterior - restante;

        if (saldoQuery.isNotEmpty) {
          await txn.update(
            'estoque_saldos',
            {
              'quantidade_atual': posterior,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            where:
                "estoque_id = ? AND business_id = ? AND finalidade = 'venda'",
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
        await txn.update(
          'consignacao_itens',
          {'quantidade_devolvida': devolvida + restante},
          where: "id = ? AND comercio_id = ?",
          whereArgs: [item['id'], u.comercioId],
        );
        await txn.insert('movimentacoes_estoque', {
          'id': IdGenerator.temporal(),
          'comercio_id': u.comercioId,
          'item_estoque_id': produtoId,
          'tipo': TipoMovimentoLoja.devolucaoConsignada.chave,
          'quantidade': restante,
          'quantidade_anterior': anterior,
          'quantidade_posterior': posterior,
          'data': DateTime.now().toIso8601String(),
          'motivo': 'Devolução no fechamento da consignação',
          'usuario_responsavel_id': u.id,
          'origem': 'consignacao',
          'referencia_id': consignacaoId,
        });
      }
      await txn.update(
        'consignacoes',
        {'status': 'fechada', 'fechada_em': DateTime.now().toIso8601String()},
        where: "id = ? AND comercio_id = ?",
        whereArgs: [consignacaoId, u.comercioId],
      );
    });
  }

  Future<String> receberMaleta({
    required String fornecedorId,
    required String nomeLote,
    String? contrato,
    String? numeroMostruario,
    String? unidadeId,
    DateTime? recebidaEm,
    DateTime? recolhimentoPrevisto,
    DateTime? dataPagamento,
    int? prazoCobrancaDias,
    String? observacoes,
    String? arquivoOrigem,
    required List<Map<String, Object?>> pecas,
  }) async {
    final user = _usuario;
    if (nomeLote.trim().isEmpty || pecas.isEmpty) {
      throw StateError('Informe a maleta e as peças.');
    }
    final db = await _databaseProvider();
    final id = IdGenerator.temporal();
    await db.transaction((tx) async {
      final now = (recebidaEm ?? DateTime.now()).toUtc().toIso8601String();
      final quantidade = pecas.fold<int>(
        0,
        (total, piece) => total + _positiveInt(piece['quantidade']),
      );
      await tx.insert('consignacoes', {
        'id': id,
        'comercio_id': user.comercioId,
        'fornecedor_id': fornecedorId,
        'lote_colecao': nomeLote.trim(),
        'nome_lote': nomeLote.trim(),
        'contrato': _nullableText(contrato),
        'numero_mostruario': _nullableText(numeroMostruario),
        'codigo_referencia': id,
        'unidade_id': unidadeId,
        'recebida_em': now,
        'data_prevista_recolhimento': recolhimentoPrevisto?.toIso8601String(),
        'data_pagamento': dataPagamento?.toIso8601String(),
        'observacoes': _nullableText(observacoes),
        'arquivo_origem': _nullableText(arquivoOrigem),
        'prazo_cobranca_dias': prazoCobrancaDias,
        'status': 'aberta',
        'criado_em': now,
        'quantidade_recebida': quantidade,
        'quantidade_disponivel': quantidade,
        'valor_total_recebido': pecas.fold<double>(
          0,
          (total, piece) =>
              total +
              _money(piece['preco']) * _positiveInt(piece['quantidade']),
        ),
      });
      for (final piece in pecas) {
        final code = _nullableText(piece['codigo']);
        final name = _nullableText(piece['nome'] ?? piece['descricao']);
        final price = _nullableMoney(piece['preco']);
        if (code == null ||
            code.isEmpty ||
            name == null ||
            name.isEmpty ||
            price == null ||
            price < 0) {
          throw StateError('Peça consignada inválida.');
        }
        for (var unit = 0; unit < _positiveInt(piece['quantidade']); unit++) {
          final pieceId = IdGenerator.temporal();
          await tx.insert('pecas_unicas', {
            'id': pieceId,
            'comercio_id': user.comercioId,
            'codigo_exclusivo': code,
            'nome': name,
            'descricao': piece['descricao'],
            'categoria': _nullableText(piece['categoria']),
            'material': piece['material'],
            'marca': piece['marca'],
            'fornecedor_id': fornecedorId,
            'custo': (piece['repasse'] as num?)?.toDouble() ?? 0,
            'preco': price,
            'lote_id': id,
            'unidade_id': unidadeId,
            'status': 'disponivel',
            'observacoes': _nullableText(piece['observacoes']),
            'data_cadastro': now,
          });
          await tx.insert('consignacao_eventos', {
            'id': IdGenerator.temporal(),
            'comercio_id': user.comercioId,
            'consignacao_id': id,
            'peca_id': pieceId,
            'tipo': 'recebimento',
            'quantidade': 1,
            'valor': price,
            'criado_em': now,
          });
        }
      }
    });
    return id;
  }

  Future<void> venderPeca(
    String pecaId, {
    String? clienteId,
    String? profissionalId,
    double? valor,
    String formaPagamento = 'pix',
  }) async {
    final user = _usuario;
    final db = await _databaseProvider();
    await db.transaction((tx) async {
      final rows = await tx.query(
        'pecas_unicas',
        where: "id=? AND comercio_id=? AND status='disponivel'",
        whereArgs: [pecaId, user.comercioId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Peça indisponível.');
      final piece = rows.single;
      final now = DateTime.now().toUtc().toIso8601String();
      final salePrice = valor ?? _money(piece['preco']);
      if (salePrice < 0 || formaPagamento.trim().isEmpty) {
        throw StateError('Dados da venda inválidos.');
      }
      final saleId = IdGenerator.temporal();
      await tx.insert('pdv_vendas', {
        'id': saleId,
        'comercio_id': user.comercioId,
        'profissional_id': profissionalId ?? user.id,
        'cliente_id': clienteId,
        'valor_total': salePrice,
        'data_venda': now,
        'status': 'concluida',
      });
      await tx.insert('pdv_venda_itens', {
        'id': '${saleId}_0',
        'pdv_venda_id': saleId,
        'produto_id': pecaId,
        'quantidade': 1,
        'valor_unitario': salePrice,
      });
      await tx.update(
        'pecas_unicas',
        {
          'status': 'vendida',
          'cliente_id': clienteId,
          'profissional_vendedor_id': profissionalId,
          'data_venda': now,
        },
        where: 'id=?',
        whereArgs: [pecaId],
      );
      await tx.insert('consignacao_eventos', {
        'id': IdGenerator.temporal(),
        'comercio_id': user.comercioId,
        'consignacao_id': piece['lote_id'],
        'peca_id': pecaId,
        'tipo': 'venda',
        'quantidade': 1,
        'valor': salePrice,
        'cliente_id': clienteId,
        'profissional_id': profissionalId,
        'venda_id': saleId,
        'forma_pagamento': formaPagamento.trim().toLowerCase(),
        'criado_em': now,
      });
      await tx.insert('movimentacoes_financeiras', {
        'id': '${saleId}_p0',
        'tipo': 'receita',
        'descricao': 'Venda PDV',
        'valor': salePrice,
        'forma_pagamento': formaPagamento.trim().toLowerCase(),
        'status': 'pago',
        'data': now,
        'data_criacao': now,
        'categoria': 'venda de produto',
        'centro_resultado': 'loja',
        'entidade_origem': 'pdv_venda',
        'entidade_origem_id': saleId,
        'cliente_id': clienteId,
        'profissional_id': profissionalId ?? user.id,
        'usuario_responsavel_id': user.id,
        'observacoes': 'Venda de peça consignada',
      });
      await tx.rawUpdate(
        '''UPDATE consignacoes SET quantidade_vendida=quantidade_vendida+1,
        quantidade_disponivel=quantidade_disponivel-1, valor_vendido=valor_vendido+?
        WHERE id=? AND comercio_id=?''',
        [salePrice, piece['lote_id'], user.comercioId],
      );
    });
  }

  /// Finaliza várias peças físicas como uma única venda/comanda.
  /// A validação de todas as peças ocorre antes de qualquer gravação e a
  /// transação inteira é revertida se uma delas já não estiver disponível.
  Future<String> venderPecas(
    Iterable<String> pecaIds, {
    required String clienteId,
    String? profissionalId,
    String formaPagamento = 'pix',
    DateTime? dataVenda,
    DateTime? dataPagamento,
    String? observacoes,
  }) async {
    final user = _usuario;
    final ids = pecaIds.toSet().toList();
    if (ids.isEmpty || clienteId.trim().isEmpty) {
      throw StateError('Selecione a cliente e ao menos uma peça.');
    }
    if (formaPagamento.trim().isEmpty) {
      throw StateError('Informe a forma de pagamento.');
    }
    final db = await _databaseProvider();
    final saleId = IdGenerator.temporal();
    await db.transaction((tx) async {
      final clients = await tx.query(
        'clientes',
        columns: ['id'],
        where: 'id=? AND comercio_id=? AND ativo=1',
        whereArgs: [clienteId, user.comercioId],
        limit: 1,
      );
      if (clients.isEmpty) throw StateError('Cliente não encontrado.');
      final pieces = <Map<String, Object?>>[];
      for (final id in ids) {
        final rows = await tx.query(
          'pecas_unicas',
          where: "id=? AND comercio_id=? AND status='disponivel'",
          whereArgs: [id, user.comercioId],
          limit: 1,
        );
        if (rows.isEmpty) throw StateError('Peça indisponível: $id.');
        pieces.add(rows.single);
      }
      final soldAt = (dataVenda ?? DateTime.now()).toUtc().toIso8601String();
      final paymentAt = (dataPagamento ?? dataVenda ?? DateTime.now())
          .toUtc()
          .toIso8601String();
      final total = pieces.fold<double>(
        0,
        (sum, piece) => sum + _money(piece['preco']),
      );
      await tx.insert('pdv_vendas', {
        'id': saleId,
        'comercio_id': user.comercioId,
        'profissional_id': profissionalId ?? user.id,
        'cliente_id': clienteId,
        'valor_total': total,
        'data_venda': soldAt,
        'status': 'concluida',
      });
      for (var index = 0; index < pieces.length; index++) {
        final piece = pieces[index];
        final pieceId = piece['id'] as String;
        final price = _money(piece['preco']);
        await tx.insert('pdv_venda_itens', {
          'id': '${saleId}_$index',
          'pdv_venda_id': saleId,
          'produto_id': pieceId,
          'quantidade': 1,
          'valor_unitario': price,
        });
        await tx.update(
          'pecas_unicas',
          {
            'status': 'vendida',
            'cliente_id': clienteId,
            'profissional_vendedor_id': profissionalId ?? user.id,
            'data_venda': soldAt,
          },
          where: "id=? AND comercio_id=? AND status='disponivel'",
          whereArgs: [pieceId, user.comercioId],
        );
        await tx.insert('consignacao_eventos', {
          'id': IdGenerator.temporal(),
          'comercio_id': user.comercioId,
          'consignacao_id': piece['lote_id'],
          'peca_id': pieceId,
          'tipo': 'venda',
          'quantidade': 1,
          'valor': price,
          'cliente_id': clienteId,
          'profissional_id': profissionalId ?? user.id,
          'venda_id': saleId,
          'forma_pagamento': formaPagamento.trim().toLowerCase(),
          'observacoes': observacoes,
          'criado_em': soldAt,
        });
        await tx.rawUpdate(
          '''UPDATE consignacoes SET quantidade_vendida=quantidade_vendida+1,
          quantidade_disponivel=quantidade_disponivel-1,
          valor_vendido=valor_vendido+? WHERE id=? AND comercio_id=?''',
          [price, piece['lote_id'], user.comercioId],
        );
      }
      await tx.insert('movimentacoes_financeiras', {
        'id': '${saleId}_p0',
        'tipo': 'receita',
        'descricao': 'Venda PDV • ${pieces.length} peça(s) consignada(s)',
        'valor': total,
        'forma_pagamento': formaPagamento.trim().toLowerCase(),
        'status': 'pago',
        'data': paymentAt,
        'data_criacao': soldAt,
        'categoria': 'venda de produto',
        'centro_resultado': 'loja',
        'entidade_origem': 'pdv_venda',
        'entidade_origem_id': saleId,
        'cliente_id': clienteId,
        'profissional_id': profissionalId ?? user.id,
        'usuario_responsavel_id': user.id,
        'observacoes': observacoes ?? 'Venda de peças consignadas',
      });
    });
    return saleId;
  }

  Future<void> devolverPeca(String pecaId, {String? observacoes}) async {
    final user = _usuario;
    final db = await _databaseProvider();
    await db.transaction((tx) async {
      final rows = await tx.query(
        'pecas_unicas',
        where: "id=? AND comercio_id=? AND status='disponivel'",
        whereArgs: [pecaId, user.comercioId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Peça indisponível para devolução.');
      }
      final piece = rows.single;
      final now = DateTime.now().toUtc().toIso8601String();
      await tx.update(
        'pecas_unicas',
        {'status': 'devolvida'},
        where: 'id=?',
        whereArgs: [pecaId],
      );
      await tx.insert('consignacao_eventos', {
        'id': IdGenerator.temporal(),
        'comercio_id': user.comercioId,
        'consignacao_id': piece['lote_id'],
        'peca_id': pecaId,
        'tipo': 'devolucao',
        'quantidade': 1,
        'valor': piece['preco'],
        'observacoes': observacoes,
        'criado_em': now,
      });
      await tx.rawUpdate(
        '''UPDATE consignacoes SET quantidade_devolvida=quantidade_devolvida+1,
        quantidade_disponivel=quantidade_disponivel-1, valor_devolvido=valor_devolvido+?
        WHERE id=? AND comercio_id=?''',
        [piece['preco'], piece['lote_id'], user.comercioId],
      );
    });
  }

  Future<Map<String, Object?>> vendaDaPeca(String pecaId) async {
    final user = _usuario;
    final db = await _databaseProvider();
    final rows = await db.rawQuery(
      '''SELECT v.*, e.forma_pagamento, e.observacoes, c.nome cliente_nome
      FROM consignacao_eventos e JOIN pdv_vendas v ON v.id=e.venda_id
      LEFT JOIN clientes c ON c.id=v.cliente_id
      WHERE e.peca_id=? AND e.comercio_id=? AND e.tipo='venda'
      ORDER BY e.criado_em DESC LIMIT 1''',
      [pecaId, user.comercioId],
    );
    if (rows.isEmpty) throw StateError('Venda não encontrada.');
    return rows.single;
  }

  Future<void> editarVendaDaPeca(
    String pecaId, {
    String? clienteId,
    required String formaPagamento,
    DateTime? dataPagamento,
    String? observacoes,
    String? profissionalId,
  }) async {
    final user = _usuario;
    final db = await _databaseProvider();
    await db.transaction((tx) async {
      final events = await tx.query(
        'consignacao_eventos',
        where: "peca_id=? AND comercio_id=? AND tipo='venda'",
        whereArgs: [pecaId, user.comercioId],
        orderBy: 'criado_em DESC',
        limit: 1,
      );
      if (events.isEmpty) throw StateError('Venda não encontrada.');
      final event = events.single;
      final saleId = event['venda_id'] as String;
      await tx.update(
        'pdv_vendas',
        {'cliente_id': clienteId, 'profissional_id': profissionalId ?? user.id},
        where: "id=? AND comercio_id=? AND status='concluida'",
        whereArgs: [saleId, user.comercioId],
      );
      await tx.update(
        'pecas_unicas',
        {
          'cliente_id': clienteId,
          'profissional_vendedor_id': profissionalId ?? user.id,
        },
        where: 'id=? AND comercio_id=?',
        whereArgs: [pecaId, user.comercioId],
      );
      await tx.update(
        'consignacao_eventos',
        {
          'cliente_id': clienteId,
          'profissional_id': profissionalId ?? user.id,
          'forma_pagamento': formaPagamento.trim().toLowerCase(),
          'observacoes': observacoes,
        },
        where: 'id=?',
        whereArgs: [event['id']],
      );
      await tx.update(
        'movimentacoes_financeiras',
        {
          'cliente_id': clienteId,
          'profissional_id': profissionalId ?? user.id,
          'forma_pagamento': formaPagamento.trim().toLowerCase(),
          if (dataPagamento != null)
            'data': dataPagamento.toUtc().toIso8601String(),
          'observacoes': observacoes,
        },
        where: 'id=?',
        whereArgs: ['${saleId}_p0'],
      );
    });
  }

  Future<void> estornarVendaDaPeca(String pecaId, String motivo) async {
    final user = _usuario;
    if (motivo.trim().isEmpty) throw StateError('Informe o motivo do estorno.');
    final db = await _databaseProvider();
    await db.transaction((tx) async {
      final pieces = await tx.query(
        'pecas_unicas',
        where: "id=? AND comercio_id=? AND status='vendida'",
        whereArgs: [pecaId, user.comercioId],
        limit: 1,
      );
      if (pieces.isEmpty) throw StateError('Peça não está vendida.');
      final piece = pieces.single;
      final events = await tx.query(
        'consignacao_eventos',
        where: "peca_id=? AND comercio_id=? AND tipo='venda'",
        whereArgs: [pecaId, user.comercioId],
        orderBy: 'criado_em DESC',
        limit: 1,
      );
      if (events.isEmpty) {
        throw StateError('Histórico da venda não encontrado.');
      }
      final event = events.single;
      final saleId = event['venda_id'] as String;
      final saleItems = await tx.query(
        'pdv_venda_itens',
        where: 'pdv_venda_id=?',
        whereArgs: [saleId],
      );
      if (saleItems.length != 1) {
        throw StateError(
          'Esta peça pertence a uma comanda com vários itens. Estorne a comanda completa.',
        );
      }
      final now = DateTime.now().toUtc().toIso8601String();
      final value = _money(event['valor']);
      await tx.update(
        'pecas_unicas',
        {
          'status': 'disponivel',
          'cliente_id': null,
          'profissional_vendedor_id': null,
          'data_venda': null,
        },
        where: 'id=? AND comercio_id=?',
        whereArgs: [pecaId, user.comercioId],
      );
      await tx.update(
        'pdv_vendas',
        {'status': 'estornada'},
        where: 'id=? AND comercio_id=?',
        whereArgs: [saleId, user.comercioId],
      );
      await tx.update(
        'movimentacoes_financeiras',
        {'status': 'estornado'},
        where: 'id=?',
        whereArgs: ['${saleId}_p0'],
      );
      await tx.insert('movimentacoes_financeiras', {
        'id': '${saleId}_estorno',
        'tipo': 'estorno',
        'descricao': 'Estorno de venda PDV',
        'valor': -value,
        'forma_pagamento': event['forma_pagamento'],
        'status': 'pago',
        'data': now,
        'data_criacao': now,
        'categoria': 'estorno de venda',
        'centro_resultado': 'loja',
        'entidade_origem': 'pdv_venda',
        'entidade_origem_id': saleId,
        'cliente_id': event['cliente_id'],
        'profissional_id': event['profissional_id'] ?? user.id,
        'usuario_responsavel_id': user.id,
        'observacoes': motivo.trim(),
      });
      await tx.insert('consignacao_eventos', {
        'id': IdGenerator.temporal(),
        'comercio_id': user.comercioId,
        'consignacao_id': piece['lote_id'],
        'peca_id': pecaId,
        'tipo': 'estorno_venda',
        'quantidade': 1,
        'valor': value,
        'venda_id': saleId,
        'observacoes': motivo.trim(),
        'criado_em': now,
      });
      await tx.rawUpdate(
        '''UPDATE consignacoes SET quantidade_vendida=quantidade_vendida-1,
        quantidade_disponivel=quantidade_disponivel+1,
        valor_vendido=valor_vendido-? WHERE id=? AND comercio_id=?''',
        [value, piece['lote_id'], user.comercioId],
      );
    });
  }

  Future<List<Map<String, Object?>>> historicoMensal(DateTime mes) async {
    final user = _usuario;
    final db = await _databaseProvider();
    final start = DateTime.utc(mes.year, mes.month);
    final end = DateTime.utc(mes.year, mes.month + 1);
    return db.rawQuery(
      '''SELECT e.*, p.codigo_exclusivo, p.nome peca_nome
      FROM consignacao_eventos e LEFT JOIN pecas_unicas p ON p.id=e.peca_id
      WHERE e.comercio_id=? AND e.criado_em>=? AND e.criado_em<? ORDER BY e.criado_em DESC''',
      [user.comercioId, start.toIso8601String(), end.toIso8601String()],
    );
  }

  Future<List<Map<String, Object?>>> fornecedores() async {
    final user = _usuario;
    final db = await _databaseProvider();
    return db.query(
      'fornecedores',
      columns: ['id', 'nome'],
      where: 'comercio_id=? AND ativo=1',
      whereArgs: [user.comercioId],
      orderBy: 'nome COLLATE NOCASE',
    );
  }

  Future<List<Map<String, Object?>>> pecas(
    String loteId, {
    String? status,
    String pesquisa = '',
    int limit = 500,
  }) async {
    final user = _usuario;
    final db = await _databaseProvider();
    final where = <String>['lote_id=?', 'comercio_id=?'];
    final args = <Object?>[loteId, user.comercioId];
    if (status != null && status.isNotEmpty) {
      where.add('status=?');
      args.add(status);
    }
    if (pesquisa.trim().isNotEmpty) {
      where.add(
        '(codigo_exclusivo LIKE ? OR categoria LIKE ? OR nome LIKE ? OR descricao LIKE ?)',
      );
      final value = '%${pesquisa.trim()}%';
      args.addAll([value, value, value, value]);
    }
    return db.query(
      'pecas_unicas',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'codigo_exclusivo COLLATE NOCASE, id',
      limit: limit.clamp(1, 1000),
    );
  }

  Future<Map<String, Object?>> detalhe(String loteId) async {
    final user = _usuario;
    final db = await _databaseProvider();
    final rows = await db.rawQuery(
      '''SELECT c.*, f.nome fornecedor_nome,
        COUNT(p.id) quantidade_real,
        SUM(CASE WHEN p.status='vendida' THEN 1 ELSE 0 END) vendidas_real,
        SUM(CASE WHEN p.status='disponivel' THEN 1 ELSE 0 END) disponiveis_real,
        SUM(CASE WHEN p.status='devolvida' THEN 1 ELSE 0 END) devolvidas_real,
        COALESCE(SUM(p.preco),0) valor_recebido_real,
        COALESCE(SUM(CASE WHEN p.status='vendida' THEN
          COALESCE((SELECT e.valor FROM consignacao_eventos e
            WHERE e.peca_id=p.id AND e.tipo='venda'
            ORDER BY e.criado_em DESC LIMIT 1),p.preco) ELSE 0 END),0) valor_vendido_real,
        COALESCE(SUM(CASE WHEN p.status='disponivel' THEN p.preco ELSE 0 END),0) valor_posse_real
        FROM consignacoes c JOIN fornecedores f ON f.id=c.fornecedor_id
        LEFT JOIN pecas_unicas p ON p.lote_id=c.id AND p.comercio_id=c.comercio_id
        WHERE c.id=? AND c.comercio_id=? GROUP BY c.id''',
      [loteId, user.comercioId],
    );
    if (rows.isEmpty) throw StateError('Remessa não encontrada.');
    return rows.single;
  }

  Future<void> fecharRemessa(
    String loteId, {
    required Iterable<String> pecasDevolvidas,
  }) async {
    final user = _usuario;
    final db = await _databaseProvider();
    await db.transaction((tx) async {
      final lot = await tx.query(
        'consignacoes',
        columns: ['id'],
        where: "id=? AND comercio_id=? AND status='aberta'",
        whereArgs: [loteId, user.comercioId],
        limit: 1,
      );
      if (lot.isEmpty) throw StateError('Remessa inexistente ou já fechada.');
      final ids = pecasDevolvidas.toSet();
      for (final id in ids) {
        final pieces = await tx.query(
          'pecas_unicas',
          where: "id=? AND lote_id=? AND comercio_id=? AND status='disponivel'",
          whereArgs: [id, loteId, user.comercioId],
          limit: 1,
        );
        if (pieces.isEmpty) {
          throw StateError('Peça inválida para devolução nesta remessa.');
        }
        final piece = pieces.single;
        final now = DateTime.now().toUtc().toIso8601String();
        await tx.update(
          'pecas_unicas',
          {'status': 'devolvida'},
          where: 'id=? AND comercio_id=?',
          whereArgs: [id, user.comercioId],
        );
        await tx.insert('consignacao_eventos', {
          'id': IdGenerator.temporal(),
          'comercio_id': user.comercioId,
          'consignacao_id': loteId,
          'peca_id': id,
          'tipo': 'devolucao',
          'quantidade': 1,
          'valor': _money(piece['preco']),
          'criado_em': now,
        });
      }
      final open = Sqflite.firstIntValue(
        await tx.rawQuery(
          "SELECT COUNT(*) FROM pecas_unicas WHERE lote_id=? AND comercio_id=? AND status IN ('disponivel','reservada','em_comanda')",
          [loteId, user.comercioId],
        ),
      );
      if ((open ?? 0) > 0) {
        throw StateError('Ainda existem peças disponíveis não selecionadas.');
      }
      final returned = Sqflite.firstIntValue(
        await tx.rawQuery(
          "SELECT COUNT(*) FROM pecas_unicas WHERE lote_id=? AND comercio_id=? AND status='devolvida'",
          [loteId, user.comercioId],
        ),
      );
      await tx.update(
        'consignacoes',
        {
          'status': 'fechada',
          'data_encerramento': DateTime.now().toUtc().toIso8601String(),
          'quantidade_devolvida': returned ?? 0,
          'quantidade_disponivel': 0,
        },
        where: 'id=? AND comercio_id=?',
        whereArgs: [loteId, user.comercioId],
      );
    });
  }

  Future<void> editarLote(
    String loteId, {
    String? nome,
    DateTime? trocaPrevista,
    DateTime? vencimentoPadrao,
    int? prazoCobrancaDias,
  }) async {
    final user = _usuario;
    final db = await _databaseProvider();
    final changed = await db.update(
      'consignacoes',
      {
        if (nome != null) 'nome_lote': nome.trim(),
        if (nome != null) 'lote_colecao': nome.trim(),
        if (trocaPrevista != null)
          'data_prevista_recolhimento': trocaPrevista.toUtc().toIso8601String(),
        if (vencimentoPadrao != null)
          'data_vencimento_padrao': vencimentoPadrao.toUtc().toIso8601String(),
        'prazo_cobranca_dias': ?prazoCobrancaDias,
      },
      where: "id=? AND comercio_id=? AND status='aberta'",
      whereArgs: [loteId, user.comercioId],
    );
    if (changed == 0) throw StateError('Lote não encontrado ou fechado.');
  }

  Future<void> alterarStatusPeca(
    String pecaId,
    String status, {
    String? observacoes,
  }) async {
    const allowed = {
      'disponivel',
      'reservada',
      'em_comanda',
      'perdida',
      'avariada',
      'transferida',
    };
    if (!allowed.contains(status)) throw StateError('Status de peça inválido.');
    final user = _usuario;
    final db = await _databaseProvider();
    await db.transaction((tx) async {
      final rows = await tx.query(
        'pecas_unicas',
        where: 'id=? AND comercio_id=?',
        whereArgs: [pecaId, user.comercioId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Peça não encontrada.');
      final piece = rows.single;
      if (const {
        'vendida',
        'devolvida',
        'perdida',
        'avariada',
        'transferida',
      }.contains(piece['status'])) {
        throw StateError('Peça encerrada não pode ser alterada.');
      }
      final now = DateTime.now().toUtc().toIso8601String();
      await tx.update(
        'pecas_unicas',
        {'status': status},
        where: 'id=?',
        whereArgs: [pecaId],
      );
      await tx.insert('consignacao_eventos', {
        'id': IdGenerator.temporal(),
        'comercio_id': user.comercioId,
        'consignacao_id': piece['lote_id'],
        'peca_id': pecaId,
        'tipo': status,
        'quantidade': 1,
        'valor': piece['preco'],
        'observacoes': observacoes,
        'criado_em': now,
      });
      if (const {'perdida', 'avariada', 'transferida'}.contains(status)) {
        await tx.rawUpdate(
          '''UPDATE consignacoes SET quantidade_disponivel=quantidade_disponivel-1,
          valor_perdido=valor_perdido+? WHERE id=? AND comercio_id=?''',
          [
            status == 'perdida' ? piece['preco'] : 0,
            piece['lote_id'],
            user.comercioId,
          ],
        );
      }
    });
  }

  Future<void> arquivarMaleta(String loteId) async {
    final user = _usuario;
    final db = await _databaseProvider();
    final open =
        Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM pecas_unicas WHERE lote_id=? AND comercio_id=? AND status IN ('disponivel','reservada','em_comanda')",
            [loteId, user.comercioId],
          ),
        ) ??
        0;
    if (open > 0) {
      throw StateError('Confira e encerre todas as peças antes de arquivar.');
    }
    final changed = await db.update(
      'consignacoes',
      {
        'status': 'arquivada',
        'data_encerramento': DateTime.now().toUtc().toIso8601String(),
      },
      where: "id=? AND comercio_id=? AND status='aberta'",
      whereArgs: [loteId, user.comercioId],
    );
    if (changed == 0) throw StateError('Lote não encontrado ou já arquivado.');
  }

  Future<List<Map<String, Object?>>> listar() async {
    final u = _usuario;
    final db = await _databaseProvider();
    return db.rawQuery(
      '''SELECT c.*, f.nome fornecedor_nome
      FROM consignacoes c JOIN fornecedores f ON f.id = c.fornecedor_id
      WHERE c.comercio_id = ? ORDER BY c.recebida_em DESC''',
      [u.comercioId],
    );
  }

  static int _positiveInt(Object? value) {
    final parsed = value is num
        ? value.toInt()
        : int.tryParse(value?.toString().trim() ?? '');
    return parsed != null && parsed > 0 ? parsed : 1;
  }

  static double _money(Object? value) => _nullableMoney(value) ?? 0;

  static double? _nullableMoney(Object? value) {
    if (value == null || value.toString().trim().toLowerCase() == 'null') {
      return null;
    }
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().trim().replaceAll(',', '.'));
  }

  static String? _nullableText(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty || text.toLowerCase() == 'null'
        ? null
        : text;
  }
}
