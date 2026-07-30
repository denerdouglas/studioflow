import 'package:sqflite/sqflite.dart';

import '../core/utils/id_generator.dart';
import '../database/database_service.dart';
import '../models/domain/acesso.dart';
import '../models/domain/loja.dart';
import '../services/product_catalog_contribution_service.dart';
import '../services/session_controller.dart';

class LojaRepository {
  final Future<Database> Function() _databaseProvider;
  LojaRepository({Future<Database> Function()? databaseProvider})
    : _databaseProvider =
          databaseProvider ?? (() => DatabaseService.instance.database);

  UsuarioAcesso get _usuario {
    final usuario = SessionController.instance.usuario;
    if (usuario == null) throw StateError('Sessão não autenticada.');
    if (!usuario.pode(ModuloPermissao.lojaSalao)) {
      throw StateError('Usuário sem permissão para a Loja do Salão.');
    }
    return usuario;
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

  Future<List<ProdutoLoja>> listarProdutos({
    String pesquisa = '',
    String? categoria,
    ModalidadeProduto? modalidade,
    bool somenteBaixo = false,
    bool incluirInativos = false,
  }) async {
    final u = _exigir(AcaoPermissao.visualizarEstoque);
    final db = await _databaseProvider();
    final where = <String>['comercio_id = ?', "estoque_destino = 'loja'"];
    final args = <Object?>[u.comercioId];
    if (!incluirInativos) {
      where.add('ativo = 1');
    }
    if (pesquisa.trim().isNotEmpty) {
      where.add('''(nome LIKE ? OR codigo_barras LIKE ? OR codigo_interno LIKE ?
        OR marca LIKE ?)''');
      final termo = '%${pesquisa.trim()}%';
      args.addAll([termo, termo, termo, termo]);
    }
    if (categoria != null && categoria.isNotEmpty) {
      where.add('categoria = ?');
      args.add(categoria);
    }
    if (modalidade != null) {
      where.add('modalidade = ?');
      args.add(modalidade.name);
    }
    if (somenteBaixo) where.add('quantidade_atual <= estoque_minimo');
    final maps = await db.query(
      'estoque',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: somenteBaixo
          ? 'quantidade_atual ASC, nome COLLATE NOCASE'
          : 'ativo DESC, nome COLLATE NOCASE',
    );
    return maps.map(ProdutoLoja.fromMap).toList();
  }

  Future<ProdutoLoja?> buscarProduto(String id) async {
    final u = _exigir(AcaoPermissao.visualizarEstoque);
    final db = await _databaseProvider();
    final maps = await db.query(
      'estoque',
      where: "id = ? AND comercio_id = ? AND estoque_destino = 'loja'",
      whereArgs: [id, u.comercioId],
      limit: 1,
    );
    return maps.isEmpty ? null : ProdutoLoja.fromMap(maps.first);
  }

  Future<ProdutoLoja?> buscarCodigo(String codigo) async {
    final u = _exigir(AcaoPermissao.visualizarEstoque);
    final valor = codigo.trim();
    if (valor.length < 4) throw StateError('Código de barras inválido.');
    final db = await _databaseProvider();
    final maps = await db.query(
      'estoque',
      where:
          "comercio_id = ? AND codigo_barras = ? AND estoque_destino = 'loja'",
      whereArgs: [u.comercioId, valor],
      limit: 1,
    );
    return maps.isEmpty ? null : ProdutoLoja.fromMap(maps.first);
  }

  Future<void> salvarProduto(ProdutoLoja produto) async {
    final u = _usuario;
    if (produto.comercioId != u.comercioId) {
      throw StateError('Produto não pertence ao comércio autenticado.');
    }
    if (produto.nome.trim().isEmpty || produto.categoria.trim().isEmpty) {
      throw StateError('Nome e categoria são obrigatórios.');
    }
    if (produto.custo < 0 ||
        produto.precoVenda < 0 ||
        produto.estoqueMinimo < 0) {
      throw StateError('Valores e estoque mínimo não podem ser negativos.');
    }
    final db = await _databaseProvider();
    final existente = await db.query(
      'estoque',
      columns: ['id'],
      where: "id = ? AND comercio_id = ? AND estoque_destino = 'loja'",
      whereArgs: [produto.id, u.comercioId],
      limit: 1,
    );
    _exigir(
      existente.isEmpty
          ? AcaoPermissao.cadastrarProduto
          : AcaoPermissao.editarProduto,
    );
    if ((produto.codigoBarras ?? '').isNotEmpty) {
      final duplicado = await db.query(
        'estoque',
        columns: ['id'],
        where:
            "comercio_id = ? AND codigo_barras = ? AND id != ? AND estoque_destino = 'loja'",
        whereArgs: [u.comercioId, produto.codigoBarras!.trim(), produto.id],
        limit: 1,
      );
      if (duplicado.isNotEmpty) {
        throw StateError('Código de barras já cadastrado neste comércio.');
      }
    }
    await db.transaction((txn) async {
      final atual = await txn.query(
        'estoque',
        where: "id = ? AND comercio_id = ? AND estoque_destino = 'loja'",
        whereArgs: [produto.id, u.comercioId],
        limit: 1,
      );
      final mapa = produto.toMap();
      if (atual.isEmpty) {
        final quantidadeInicial = produto.quantidadeAtual;
        mapa['quantidade_atual'] = 0.0;
        await txn.insert('estoque', mapa);
        final barcode = produto.codigoBarras?.trim() ?? '';
        if (barcode.isNotEmpty) {
          await ProductCatalogContributionService.enqueue(
            txn,
            user: u,
            barcode: barcode,
            name: produto.nome,
            brand: produto.marca,
            description: produto.descricao,
            category: produto.categoria,
            imageUrl: produto.imagem,
            unit: produto.unidade,
            source: produto.origemCatalogo,
          );
        }
        if (quantidadeInicial > 0) {
          await _movimentarTxn(
            txn,
            produtoId: produto.id,
            tipo: TipoMovimentoLoja.entradaManual,
            quantidade: quantidadeInicial,
            origem: 'cadastro_produto',
            observacao: 'Estoque inicial do cadastro',
          );
        }
      } else {
        mapa.remove('quantidade_atual');
        mapa.remove('data_cadastro');
        await txn.update(
          'estoque',
          mapa,
          where: "id = ? AND comercio_id = ? AND estoque_destino = 'loja'",
          whereArgs: [produto.id, u.comercioId],
        );
      }
      await _sincronizarReposicaoTxn(txn, produto.id);
    });
  }

  Future<void> alterarStatusProduto(String id, bool ativo) async {
    final u = _exigir(AcaoPermissao.editarProduto);
    final db = await _databaseProvider();
    await db.update(
      'estoque',
      {
        'ativo': ativo ? 1 : 0,
        'atualizado_em': DateTime.now().toIso8601String(),
      },
      where: "id = ? AND comercio_id = ? AND estoque_destino = 'loja'",
      whereArgs: [id, u.comercioId],
    );
  }

  Future<void> movimentar({
    required String produtoId,
    required TipoMovimentoLoja tipo,
    required double quantidade,
    required String origem,
    String? observacao,
    String? referenciaId,
    bool permitirNegativo = false,
    String? justificativaNegativo,
  }) async {
    final usuario = _exigir(AcaoPermissao.movimentarEstoque);
    if (permitirNegativo && usuario.funcao != FuncaoUsuario.dono) {
      throw StateError('Somente o Dono pode autorizar estoque negativo.');
    }
    if (permitirNegativo && (justificativaNegativo ?? '').trim().isEmpty) {
      throw StateError('Informe a justificativa para estoque negativo.');
    }
    final db = await _databaseProvider();
    await db.transaction((txn) async {
      await _movimentarTxn(
        txn,
        produtoId: produtoId,
        tipo: tipo,
        quantidade: quantidade,
        origem: origem,
        observacao: observacao,
        referenciaId: referenciaId,
        permitirNegativo: permitirNegativo,
        justificativaNegativo: justificativaNegativo,
      );
      await _sincronizarReposicaoTxn(txn, produtoId);
    });
  }

  Future<void> _movimentarTxn(
    Transaction txn, {
    required String produtoId,
    required TipoMovimentoLoja tipo,
    required double quantidade,
    required String origem,
    String? observacao,
    String? referenciaId,
    bool permitirNegativo = false,
    String? justificativaNegativo,
  }) async {
    final u = _usuario;
    if (quantidade <= 0) {
      throw StateError('Quantidade deve ser maior que zero.');
    }
    final maps = await txn.query(
      'estoque',
      where: "id = ? AND comercio_id = ? AND estoque_destino = 'loja'",
      whereArgs: [produtoId, u.comercioId],
      limit: 1,
    );
    if (maps.isEmpty) {
      throw StateError('Produto não encontrado neste comércio.');
    }
    final anterior = (maps.first['quantidade_atual'] as num).toDouble();
    final posterior = tipo == TipoMovimentoLoja.ajuste
        ? quantidade
        : anterior + (tipo.entrada ? quantidade : -quantidade);
    if (posterior < 0 && !permitirNegativo) {
      throw StateError('Estoque insuficiente. A operação foi cancelada.');
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
      'tipo': tipo.chave,
      'quantidade': quantidade,
      'quantidade_anterior': anterior,
      'quantidade_posterior': posterior,
      'data': DateTime.now().toIso8601String(),
      'motivo': observacao,
      'usuario_responsavel_id': u.id,
      'origem': origem,
      'referencia_id': referenciaId,
      'justificativa_negativo': justificativaNegativo,
    });
  }

  Future<List<Map<String, Object?>>> historico(String produtoId) async {
    final u = _usuario;
    final db = await _databaseProvider();
    return db.query(
      'movimentacoes_estoque',
      where: 'comercio_id = ? AND item_estoque_id = ?',
      whereArgs: [u.comercioId, produtoId],
      orderBy: 'data DESC',
    );
  }

  Future<List<FornecedorLoja>> listarFornecedores({bool ativos = false}) async {
    final u = _usuario;
    final db = await _databaseProvider();
    final maps = await db.query(
      'fornecedores',
      where: ativos ? 'comercio_id = ? AND ativo = 1' : 'comercio_id = ?',
      whereArgs: [u.comercioId],
      orderBy: 'ativo DESC, nome COLLATE NOCASE',
    );
    return maps.map(FornecedorLoja.fromMap).toList();
  }

  Future<void> salvarFornecedor(FornecedorLoja fornecedor) async {
    final u = _exigir(AcaoPermissao.cadastrarFornecedor);
    if (fornecedor.comercioId != u.comercioId ||
        fornecedor.nome.trim().isEmpty) {
      throw StateError('Fornecedor inválido para este comércio.');
    }
    final db = await _databaseProvider();
    final agora = DateTime.now().toIso8601String();
    await db.insert('fornecedores', {
      'id': fornecedor.id,
      'comercio_id': u.comercioId,
      'nome': fornecedor.nome.trim(),
      'nome_fantasia': fornecedor.nomeFantasia,
      'documento': fornecedor.documento,
      'telefone': fornecedor.telefone,
      'whatsapp': fornecedor.whatsapp,
      'email': fornecedor.email,
      'endereco': fornecedor.endereco,
      'contato_responsavel': fornecedor.contato,
      'prazo_medio_dias': fornecedor.prazoDias,
      'formas_pagamento': fornecedor.formasPagamento,
      'valor_minimo_pedido': fornecedor.minimoPedido,
      'entrega_disponivel': fornecedor.entrega ? 1 : 0,
      'regioes_atendidas': fornecedor.regioes,
      'observacoes': fornecedor.observacoes,
      'ativo': fornecedor.ativo ? 1 : 0,
      'criado_em': agora,
      'atualizado_em': agora,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String> finalizarVenda({
    required List<ItemCarrinho> itens,
    required double desconto,
    required Map<String, double> pagamentos,
    String? clienteId,
    String? observacoes,
  }) async {
    final u = _exigir(AcaoPermissao.realizarVenda);
    if (desconto > 0) _exigir(AcaoPermissao.aplicarDesconto);
    if (itens.isEmpty) throw StateError('O carrinho está vazio.');
    final subtotal = itens.fold<double>(0, (v, i) => v + i.total);
    final total = subtotal - desconto;
    if (total < 0) throw StateError('Desconto maior que o valor da venda.');
    final pago = pagamentos.values.fold<double>(0, (a, b) => a + b);
    if ((pago - total).abs() > 0.01) {
      throw StateError('A soma dos pagamentos deve ser igual ao total.');
    }
    final db = await _databaseProvider();
    final vendaId = IdGenerator.temporal();
    await db.transaction((txn) async {
      final numero = 'V${DateTime.now().millisecondsSinceEpoch}';
      await txn.insert('vendas', {
        'id': vendaId,
        'numero': numero,
        'comercio_id': u.comercioId,
        'cliente_id': clienteId,
        'usuario_id': u.id,
        'subtotal': subtotal,
        'desconto': desconto,
        'total': total,
        'status': 'concluida',
        'observacoes': observacoes,
        'criada_em': DateTime.now().toIso8601String(),
      });
      for (var index = 0; index < itens.length; index++) {
        final item = itens[index];
        await txn.insert('venda_itens', {
          'id': '${vendaId}_$index',
          'venda_id': vendaId,
          'comercio_id': u.comercioId,
          'produto_id': item.produto.id,
          'nome_produto': item.produto.nome,
          'quantidade': item.quantidade,
          'preco_unitario': item.produto.precoVenda,
          'desconto': item.desconto,
          'total': item.total,
        });
        await _movimentarTxn(
          txn,
          produtoId: item.produto.id,
          tipo: TipoMovimentoLoja.venda,
          quantidade: item.quantidade,
          origem: 'venda',
          referenciaId: vendaId,
          observacao: 'Baixa automática da venda $numero',
        );
        await _sincronizarReposicaoTxn(txn, item.produto.id);
        if (item.produto.modalidade == ModalidadeProduto.consignado) {
          await txn.rawUpdate(
            '''UPDATE consignacao_itens
            SET quantidade_vendida = quantidade_vendida + ?
            WHERE produto_id = ? AND comercio_id = ? AND consignacao_id IN
              (SELECT id FROM consignacoes WHERE status = 'aberta')''',
            [item.quantidade, item.produto.id, u.comercioId],
          );
        }
      }
      var p = 0;
      for (final pagamento in pagamentos.entries) {
        await txn.insert('venda_pagamentos', {
          'id': '${vendaId}_p${p++}',
          'venda_id': vendaId,
          'comercio_id': u.comercioId,
          'forma': pagamento.key,
          'valor': pagamento.value,
          'status': 'confirmado_manual',
        });
      }
    });
    return vendaId;
  }

  Future<void> cancelarVenda(String vendaId, String motivo) async {
    final u = _exigir(AcaoPermissao.cancelarVenda);
    if (motivo.trim().isEmpty) {
      throw StateError('Informe o motivo do cancelamento.');
    }
    final db = await _databaseProvider();
    await db.transaction((txn) async {
      final venda = await txn.query(
        'vendas',
        where: 'id = ? AND comercio_id = ? AND status = ?',
        whereArgs: [vendaId, u.comercioId, 'concluida'],
        limit: 1,
      );
      if (venda.isEmpty) {
        throw StateError('Venda não encontrada ou já cancelada.');
      }
      final itens = await txn.query(
        'venda_itens',
        where: 'venda_id = ?',
        whereArgs: [vendaId],
      );
      for (final item in itens) {
        await _movimentarTxn(
          txn,
          produtoId: item['produto_id'] as String,
          tipo: TipoMovimentoLoja.cancelamentoVenda,
          quantidade: (item['quantidade'] as num).toDouble(),
          origem: 'cancelamento_venda',
          referenciaId: vendaId,
          observacao: motivo,
        );
      }
      await txn.update(
        'vendas',
        {
          'status': 'cancelada',
          'cancelada_em': DateTime.now().toIso8601String(),
          'observacoes': motivo,
        },
        where: "id = ? AND comercio_id = ?",
        whereArgs: [vendaId, u.comercioId],
      );
    });
  }

  Future<List<Map<String, Object?>>> listarVendas() async {
    final u = _usuario;
    final db = await _databaseProvider();
    return db.query(
      'vendas',
      where: 'comercio_id = ?',
      whereArgs: [u.comercioId],
      orderBy: 'criada_em DESC',
    );
  }

  Future<void> _sincronizarReposicaoTxn(
    Transaction txn,
    String produtoId,
  ) async {
    final u = _usuario;
    final maps = await txn.query(
      'estoque',
      where:
          "id = ? AND comercio_id = ? AND ativo = 1 AND estoque_destino = 'loja'",
      whereArgs: [produtoId, u.comercioId],
      limit: 1,
    );
    if (maps.isEmpty) return;
    final p = ProdutoLoja.fromMap(maps.first);
    if (p.estoqueBaixo) {
      final existentes = await txn.query(
        'reposicoes',
        columns: ['id'],
        where:
            "comercio_id = ? AND produto_id = ? AND status NOT IN ('recebido','cancelado')",
        whereArgs: [u.comercioId, produtoId],
        limit: 1,
      );
      if (existentes.isEmpty) {
        final agora = DateTime.now().toIso8601String();
        await txn.insert('reposicoes', {
          'id': IdGenerator.temporal(),
          'comercio_id': u.comercioId,
          'produto_id': produtoId,
          'quantidade_desejada': p.sugestaoReposicao,
          'fornecedor_id': p.fornecedorPrincipalId,
          'status': 'rascunho',
          'manual': 0,
          'criado_em': agora,
          'atualizado_em': agora,
        });
      }
    }
  }

  Future<List<Map<String, Object?>>> listarReposicoes() async {
    final u = _usuario;
    final db = await _databaseProvider();
    return db.rawQuery(
      '''SELECT r.*, e.nome produto_nome,
      e.quantidade_atual, e.estoque_minimo, f.nome fornecedor_nome
      FROM reposicoes r JOIN estoque e ON e.id = r.produto_id
      LEFT JOIN fornecedores f ON f.id = r.fornecedor_id
      WHERE r.comercio_id = ? AND e.estoque_destino = 'loja' ORDER BY r.atualizado_em DESC''',
      [u.comercioId],
    );
  }

  Future<void> salvarOferta({
    required String? produtoId,
    required OfertaReposicao oferta,
  }) async {
    final u = _usuario;
    final db = await _databaseProvider();
    await db.insert('ofertas_reposicao', {
      'id': oferta.id,
      'comercio_id': u.comercioId,
      'produto_id': produtoId,
      'titulo': oferta.titulo,
      'quantidade_embalagem': oferta.quantidadeEmbalagem,
      'preco': oferta.preco,
      'frete': oferta.frete,
      'prazo_dias': oferta.prazoDias,
      'avaliacao': oferta.avaliacao,
      'plataforma': oferta.plataforma,
      'vendedor': oferta.vendedor,
      'link': oferta.link,
      'habitual': oferta.habitual ? 1 : 0,
      'pesquisada_em': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<OfertaReposicao>> listarOfertas({String? produtoId}) async {
    final u = _usuario;
    final db = await _databaseProvider();
    final maps = await db.query(
      'ofertas_reposicao',
      where: produtoId == null
          ? 'comercio_id = ?'
          : 'comercio_id = ? AND produto_id = ?',
      whereArgs: produtoId == null ? [u.comercioId] : [u.comercioId, produtoId],
      orderBy: '(preco + frete) ASC',
    );
    return maps
        .map(
          (m) => OfertaReposicao(
            id: m['id'] as String,
            plataforma: m['plataforma'] as String,
            titulo: m['titulo'] as String,
            quantidadeEmbalagem: (m['quantidade_embalagem'] as num).toDouble(),
            preco: (m['preco'] as num).toDouble(),
            frete: (m['frete'] as num).toDouble(),
            prazoDias: m['prazo_dias'] as int?,
            avaliacao: (m['avaliacao'] as num?)?.toDouble(),
            vendedor: m['vendedor'] as String?,
            link: m['link'] as String?,
            habitual: m['habitual'] == 1,
          ),
        )
        .toList();
  }
}
