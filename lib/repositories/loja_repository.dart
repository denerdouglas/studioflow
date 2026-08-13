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
    bool somenteUsoInterno = false,
    bool somenteAtivos = false,
  }) async {
    final u = _exigir(AcaoPermissao.visualizarEstoque);
    final db = await _databaseProvider();
    final where = <String>['e.comercio_id = ?'];

    if (somenteAtivos) {
      where.add("e.tipo_produto = 'ativo_imobilizado'");
    } else if (somenteUsoInterno) {
      where.add("(e.tipo_produto = 'uso_interno' OR e.tipo_produto = 'ambos')");
    } else {
      where.add(
        "(e.tipo_produto = 'venda' OR e.tipo_produto = 'ambos' OR e.estoque_destino = 'loja')",
      );
    }

    final args = <Object?>[u.comercioId];
    if (!incluirInativos) {
      where.add('e.ativo = 1');
    }
    if (pesquisa.trim().isNotEmpty) {
      where.add(
        '''(e.nome LIKE ? OR e.codigo_barras LIKE ? OR e.codigo_interno LIKE ?
        OR e.marca LIKE ? OR e.categoria LIKE ?)''',
      );
      final termo = '%${pesquisa.trim()}%';
      args.addAll([termo, termo, termo, termo, termo]);
    }
    if (categoria != null && categoria.isNotEmpty) {
      where.add('e.categoria = ?');
      args.add(categoria);
    }
    if (modalidade != null) {
      where.add('e.modalidade = ?');
      args.add(modalidade.name);
    }
    if (somenteBaixo) {
      where.add(
        'COALESCE(s.quantidade_atual, e.quantidade_atual) <= COALESCE(s.estoque_minimo, e.estoque_minimo)',
      );
    }

    final query =
        '''
      SELECT e.*, COALESCE(s.quantidade_atual, e.quantidade_atual) as quantidade_atual, COALESCE(s.estoque_minimo, e.estoque_minimo) as estoque_minimo
      FROM estoque e
      LEFT JOIN estoque_saldos s ON e.id = s.estoque_id AND s.finalidade = 'venda'
      WHERE ${where.join(' AND ')}
      ORDER BY ${somenteBaixo ? 'quantidade_atual ASC, e.nome COLLATE NOCASE' : 'e.ativo DESC, e.nome COLLATE NOCASE'}
    ''';

    final maps = await db.rawQuery(query, args);
    return maps.map(ProdutoLoja.fromMap).toList();
  }

  Future<ProdutoLoja?> buscarProduto(String id) async {
    final u = _exigir(AcaoPermissao.visualizarEstoque);
    final db = await _databaseProvider();
    final query = '''
      SELECT e.*, COALESCE(s.quantidade_atual, e.quantidade_atual) as quantidade_atual, COALESCE(s.estoque_minimo, e.estoque_minimo) as estoque_minimo
      FROM estoque e
      LEFT JOIN estoque_saldos s ON e.id = s.estoque_id AND s.finalidade = 'venda'
      WHERE e.id = ? AND e.comercio_id = ? AND (e.tipo_produto = 'venda' OR e.tipo_produto = 'ambos' OR e.estoque_destino = 'loja')
      LIMIT 1
    ''';
    final maps = await db.rawQuery(query, [id, u.comercioId]);
    return maps.isEmpty ? null : ProdutoLoja.fromMap(maps.first);
  }

  Future<ProdutoLoja?> buscarCodigo(String codigo) async {
    final u = _exigir(AcaoPermissao.visualizarEstoque);
    final valor = codigo.trim();
    if (valor.length < 4) throw StateError('Código de barras inválido.');
    final db = await _databaseProvider();

    final pecas = await db.query(
      'pecas_unicas',
      where: 'comercio_id = ? AND codigo_exclusivo = ?',
      whereArgs: [u.comercioId, valor],
      limit: 1,
    );
    if (pecas.isNotEmpty) {
      final p = pecas.first;
      if (p['status'] != 'disponivel') {
        throw StateError(
          'Peça única não está disponível (status: ${p['status']}).',
        );
      }
      return ProdutoLoja(
        id: p['id'] as String,
        comercioId: u.comercioId,
        nome: p['nome'] as String,
        categoria: 'Peça Única',
        tipoProduto: 'venda',
        tipo: 'peca_unica',
        modalidade: ModalidadeProduto.proprio,
        custo: (p['custo'] as num).toDouble(),
        precoVenda: (p['preco'] as num).toDouble(),
        margem: 0,
        quantidadeAtual: 1,
        estoqueMinimo: 0,
        quantidadeSugerida: 0,
        unidade: 'un',
        quantidadeEmbalagem: 1,
        ativo: true,
        criadoEm: DateTime.parse(p['data_cadastro'] as String),
        atualizadoEm: DateTime.now(),
      );
    }

    final query = '''
      SELECT e.*, COALESCE(s.quantidade_atual, e.quantidade_atual) as quantidade_atual, COALESCE(s.estoque_minimo, e.estoque_minimo) as estoque_minimo
      FROM estoque e
      LEFT JOIN estoque_saldos s ON e.id = s.estoque_id AND s.finalidade = 'venda'
      WHERE e.comercio_id = ? AND e.codigo_barras = ? AND (e.tipo_produto = 'venda' OR e.tipo_produto = 'ambos' OR e.estoque_destino = 'loja')
      LIMIT 1
    ''';
    final maps = await db.rawQuery(query, [u.comercioId, valor]);
    return maps.isEmpty ? null : ProdutoLoja.fromMap(maps.first);
  }

  Future<List<ProdutoLoja>> listarItensParaVenda({String pesquisa = ''}) async {
    final products = await listarProdutos(pesquisa: pesquisa);
    final user = _exigir(AcaoPermissao.visualizarEstoque);
    final db = await _databaseProvider();
    final where = <String>["comercio_id=?", "status='disponivel'"];
    final args = <Object?>[user.comercioId];
    if (pesquisa.trim().isNotEmpty) {
      where.add('(nome LIKE ? OR codigo_exclusivo LIKE ? OR categoria LIKE ?)');
      final query = '%${pesquisa.trim()}%';
      args.addAll([query, query, query]);
    }
    final pieces = await db.query(
      'pecas_unicas',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'nome COLLATE NOCASE',
      limit: 500,
    );
    return [
      ...products,
      ...pieces.map(
        (piece) => ProdutoLoja(
          id: piece['id'] as String,
          comercioId: user.comercioId,
          nome: piece['nome'] as String,
          descricao: piece['descricao'] as String?,
          categoria: piece['categoria'] as String? ?? 'Consignação',
          tipoProduto: 'venda',
          tipo: 'peca_unica',
          modalidade: ModalidadeProduto.consignado,
          custo: (piece['custo'] as num?)?.toDouble() ?? 0,
          precoVenda: (piece['preco'] as num).toDouble(),
          margem: 0,
          quantidadeAtual: 1,
          estoqueMinimo: 0,
          quantidadeSugerida: 0,
          unidade: 'un',
          quantidadeEmbalagem: 1,
          ativo: true,
          codigoInterno: piece['codigo_exclusivo'] as String,
          criadoEm:
              DateTime.tryParse('${piece['data_cadastro']}') ?? DateTime.now(),
          atualizadoEm: DateTime.now(),
        ),
      ),
    ];
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
      where:
          "id = ? AND comercio_id = ? AND (tipo_produto = 'venda' OR tipo_produto = 'ambos' OR estoque_destino = 'loja')",
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
            "comercio_id = ? AND codigo_barras = ? AND id != ? AND (tipo_produto = 'venda' OR tipo_produto = 'ambos' OR estoque_destino = 'loja')",
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
        where:
            "id = ? AND comercio_id = ? AND (tipo_produto = 'venda' OR tipo_produto = 'ambos' OR estoque_destino = 'loja')",
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

        final agoraStr = DateTime.now().toUtc().toIso8601String();
        await txn.insert('estoque_saldos', {
          'id': DateTime.now().microsecondsSinceEpoch.toString(),
          'business_id': u.comercioId,
          'estoque_id': produto.id,
          'finalidade': 'venda',
          'quantidade_atual': 0.0,
          'estoque_minimo': produto.estoqueMinimo,
          'created_at': agoraStr,
          'updated_at': agoraStr,
        });

        if (quantidadeInicial > 0) {
          await _movimentarTxn(
            txn,
            produtoId: produto.id,
            tipo: TipoMovimentoLoja.entradaManual,
            quantidade: quantidadeInicial,
            origem: 'cadastro_inicial',
            observacao: 'Saldo inicial',
          );
        }
      } else {
        mapa.remove('quantidade_atual');
        mapa.remove('data_cadastro');
        await txn.update(
          'estoque',
          mapa,
          where: "id = ? AND comercio_id = ?",
          whereArgs: [produto.id, u.comercioId],
        );

        await txn.update(
          'estoque_saldos',
          {
            'quantidade_atual': produto.quantidadeAtual,
            'estoque_minimo': produto.estoqueMinimo,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: "estoque_id = ? AND business_id = ? AND finalidade = 'venda'",
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
      where:
          "id = ? AND comercio_id = ? AND (tipo_produto = 'venda' OR tipo_produto = 'ambos' OR estoque_destino = 'loja')",
      whereArgs: [id, u.comercioId],
    );
  }

  Future<void> movimentar({
    required String produtoId,
    required TipoMovimentoLoja tipo,
    required double quantidade,
    required String origem,
    String finalidade = 'venda',
    String? observacao,
    String? referenciaId,
    bool permitirNegativo = false,
    String? justificativaNegativo,
  }) async {
    final usuario = _exigir(AcaoPermissao.movimentarEstoque);
    final manual = const {
      TipoMovimentoLoja.entradaManual,
      TipoMovimentoLoja.saidaManual,
      TipoMovimentoLoja.ajuste,
      TipoMovimentoLoja.perda,
      TipoMovimentoLoja.avaria,
    }.contains(tipo);
    if (usuario.funcao == FuncaoUsuario.gerente &&
        manual &&
        (observacao ?? '').trim().isEmpty) {
      throw StateError('Informe o motivo da movimentação manual.');
    }
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
        finalidade: finalidade,
        observacao: observacao,
        referenciaId: referenciaId,
        permitirNegativo: permitirNegativo,
        justificativaNegativo: justificativaNegativo,
      );
      if (finalidade == 'venda') {
        await _sincronizarReposicaoTxn(txn, produtoId);
      }
    });
  }

  Future<void> _movimentarTxn(
    Transaction txn, {
    required String produtoId,
    required TipoMovimentoLoja tipo,
    required double quantidade,
    required String origem,
    String finalidade = 'venda',
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
      'estoque_saldos',
      where: "estoque_id = ? AND business_id = ? AND finalidade = ?",
      whereArgs: [produtoId, u.comercioId, finalidade],
      limit: 1,
    );
    if (maps.isEmpty) {
      throw StateError(
        'Produto não encontrado ou saldo não inicializado para esta finalidade.',
      );
    }
    final anterior = (maps.first['quantidade_atual'] as num).toDouble();
    final posterior = tipo == TipoMovimentoLoja.ajuste
        ? quantidade
        : anterior + (tipo.entrada ? quantidade : -quantidade);
    if (posterior < 0 && !permitirNegativo) {
      throw StateError('Estoque insuficiente. A operação foi cancelada.');
    }

    // Fallback: se a finalidade for venda, ainda atualizamos o legado no estoque para manter telas velhas funcionando.
    if (finalidade == 'venda') {
      await txn.update(
        'estoque',
        {
          'quantidade_atual': posterior,
          'atualizado_em': DateTime.now().toIso8601String(),
        },
        where: "id = ? AND comercio_id = ?",
        whereArgs: [produtoId, u.comercioId],
      );
    }

    await txn.update(
      'estoque_saldos',
      {
        'quantidade_atual': posterior,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: "estoque_id = ? AND business_id = ? AND finalidade = ?",
      whereArgs: [produtoId, u.comercioId, finalidade],
    );
    await txn.insert('movimentacoes_estoque', {
      'id': IdGenerator.temporal(),
      'comercio_id': u.comercioId,
      'item_estoque_id': produtoId,
      'tipo': tipo.chave,
      'quantidade': quantidade,
      'quantidade_anterior': anterior,
      'quantidade_posterior': posterior,
      'finalidade': finalidade,
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

  Future<void> alterarStatusFornecedor(String id, bool ativo) async {
    final user = _exigir(AcaoPermissao.cadastrarFornecedor);
    final db = await _databaseProvider();
    final changed = await db.update(
      'fornecedores',
      {
        'ativo': ativo ? 1 : 0,
        'atualizado_em': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id=? AND comercio_id=?',
      whereArgs: [id, user.comercioId],
    );
    if (changed == 0) throw StateError('Fornecedor não encontrado.');
  }

  Future<String> finalizarVenda({
    required List<ItemCarrinho> itens,
    required double desconto,
    required Map<String, double> pagamentos,
    required String profissionalId,
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
      await txn.insert('pdv_vendas', {
        'id': vendaId,
        'comercio_id': u.comercioId,
        'profissional_id': profissionalId,
        'cliente_id': clienteId,
        'valor_total': total,
        'data_venda': DateTime.now().toIso8601String(),
        'status': 'concluida',
      });
      for (var index = 0; index < itens.length; index++) {
        final item = itens[index];
        final pecas = await txn.query(
          'pecas_unicas',
          where: 'id = ? AND comercio_id = ?',
          whereArgs: [item.produto.id, u.comercioId],
          limit: 1,
        );
        final peca = pecas.firstOrNull;
        await txn.insert('pdv_venda_itens', {
          'id': '${vendaId}_$index',
          'pdv_venda_id': vendaId,
          'produto_id': item.produto.id,
          'quantidade': item.quantidade,
          'valor_unitario': item.produto.precoVenda,
        });

        if (peca != null) {
          if (item.quantidade > 1) {
            throw StateError(
              'Peça única não pode ser vendida mais de uma vez na mesma venda.',
            );
          }
          final changed = await txn.update(
            'pecas_unicas',
            {
              'status': 'vendida',
              'cliente_id': clienteId,
              'profissional_vendedor_id': profissionalId,
              'data_venda': DateTime.now().toIso8601String(),
            },
            where: 'id = ? AND comercio_id = ? AND status = ?',
            whereArgs: [item.produto.id, u.comercioId, 'disponivel'],
          );
          if (changed == 0) {
            throw StateError('Peça única já vendida ou indisponível.');
          }
          final now = DateTime.now().toUtc().toIso8601String();
          await txn.insert('consignacao_eventos', {
            'id': IdGenerator.temporal(),
            'comercio_id': u.comercioId,
            'consignacao_id': peca['lote_id'],
            'peca_id': item.produto.id,
            'tipo': 'venda',
            'quantidade': 1,
            'valor': item.produto.precoVenda,
            'cliente_id': clienteId,
            'profissional_id': profissionalId,
            'venda_id': vendaId,
            'forma_pagamento': pagamentos.keys.join(','),
            'criado_em': now,
          });
          await txn.rawUpdate(
            '''UPDATE consignacoes SET
              quantidade_vendida=COALESCE(quantidade_vendida,0)+1,
              quantidade_disponivel=MAX(0,COALESCE(quantidade_disponivel,0)-1),
              valor_vendido=COALESCE(valor_vendido,0)+?
              WHERE id=? AND comercio_id=?''',
            [item.produto.precoVenda, peca['lote_id'], u.comercioId],
          );
        } else {
          await _movimentarTxn(
            txn,
            produtoId: item.produto.id,
            tipo: TipoMovimentoLoja.venda,
            quantidade: item.quantidade,
            origem: 'venda',
            referenciaId: vendaId,
            observacao: 'Baixa automática da venda',
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
      }
      var p = 0;
      for (final pagamento in pagamentos.entries) {
        await txn.insert('movimentacoes_financeiras', {
          'id': '${vendaId}_p${p++}',
          'tipo': 'receita',
          'descricao': 'Venda PDV',
          'valor': pagamento.value,
          'forma_pagamento': pagamento.key,
          'status': 'pago',
          'data': DateTime.now().toIso8601String(),
          'data_criacao': DateTime.now().toIso8601String(),
          'categoria': 'venda de produto',
          'centro_resultado': 'loja',
          'entidade_origem': 'pdv_venda',
          'entidade_origem_id': vendaId,
          'cliente_id': clienteId,
          'profissional_id': profissionalId,
          'usuario_responsavel_id': u.id,
          'observacoes': observacoes,
        });
      }
      final profs = await txn.query(
        'profissionais',
        where: 'id = ?',
        whereArgs: [profissionalId],
        limit: 1,
      );
      if (profs.isNotEmpty) {
        final prof = profs.first;
        final comissaoProdutos =
            (prof['comissao_produtos'] as num?)?.toDouble() ??
            (prof['percentual_comissao'] as num?)?.toDouble() ??
            0.0;
        if (comissaoProdutos > 0) {
          final valorComissao = total * (comissaoProdutos / 100);
          final tableInfo = await txn.rawQuery("PRAGMA table_info(comissoes)");
          final comissaoMap = <String, Object?>{
            'id': '${vendaId}_com',
            'profissional_id': profissionalId,
            'valor_servico': total,
            'percentual_comissao': comissaoProdutos,
            'valor_comissao': valorComissao,
            'data_geracao': DateTime.now().toIso8601String(),
            'status': 'pendente',
            'observacoes': 'Comissão PDV',
          };
          if (tableInfo.any((c) => c['name'] == 'pdv_venda_id')) {
            comissaoMap['pdv_venda_id'] = vendaId;
          }
          if (tableInfo.any((c) => c['name'] == 'agendamento_id')) {
            comissaoMap['agendamento_id'] = vendaId;
          }
          if (tableInfo.any((c) => c['name'] == 'servico_id')) {
            comissaoMap['servico_id'] = 'pdv';
          }
          try {
            await txn.insert('comissoes', comissaoMap);
          } catch (_) {}
        }
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
        'pdv_vendas',
        where: 'id = ? AND comercio_id = ? AND status = ?',
        whereArgs: [vendaId, u.comercioId, 'concluida'],
        limit: 1,
      );
      if (venda.isEmpty) {
        throw StateError('Venda não encontrada ou já cancelada.');
      }
      final itens = await txn.query(
        'pdv_venda_itens',
        where: 'pdv_venda_id = ?',
        whereArgs: [vendaId],
      );
      for (final item in itens) {
        final pecas = await txn.query(
          'pecas_unicas',
          where: 'id = ? AND comercio_id = ?',
          whereArgs: [item['produto_id'], u.comercioId],
          limit: 1,
        );
        if (pecas.isNotEmpty) {
          final peca = pecas.single;
          await txn.update(
            'pecas_unicas',
            {
              'status': 'disponivel',
              'cliente_id': null,
              'profissional_vendedor_id': null,
              'data_venda': null,
              'comissao': null,
            },
            where: 'id = ? AND comercio_id = ?',
            whereArgs: [item['produto_id'], u.comercioId],
          );
          await txn.insert('consignacao_eventos', {
            'id': IdGenerator.temporal(),
            'comercio_id': u.comercioId,
            'consignacao_id': peca['lote_id'],
            'peca_id': item['produto_id'],
            'tipo': 'cancelamento_venda',
            'quantidade': 1,
            'valor': item['valor_unitario'],
            'observacoes': motivo,
            'venda_id': vendaId,
            'criado_em': DateTime.now().toUtc().toIso8601String(),
          });
          await txn.rawUpdate(
            '''UPDATE consignacoes SET
              quantidade_vendida=MAX(0,COALESCE(quantidade_vendida,0)-1),
              quantidade_disponivel=COALESCE(quantidade_disponivel,0)+1,
              valor_vendido=MAX(0,COALESCE(valor_vendido,0)-?)
              WHERE id=? AND comercio_id=?''',
            [item['valor_unitario'], peca['lote_id'], u.comercioId],
          );
        } else {
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
      }
      await txn.update(
        'pdv_vendas',
        {'status': 'cancelada'},
        where: "id = ? AND comercio_id = ?",
        whereArgs: [vendaId, u.comercioId],
      );
      // Histórico financeiro e comissões nunca são apagados. A origem é
      // marcada como estornada e um contramovimento registra o efeito.
      final finances = await txn.query(
        'movimentacoes_financeiras',
        where: 'id LIKE ?',
        whereArgs: ['${vendaId}_p%'],
      );
      final now = DateTime.now().toUtc().toIso8601String();
      for (var index = 0; index < finances.length; index++) {
        final finance = finances[index];
        if (finance['status'] == 'estornado') continue;
        await txn.update(
          'movimentacoes_financeiras',
          {'status': 'estornado'},
          where: 'id = ?',
          whereArgs: [finance['id']],
        );
        await txn.insert('movimentacoes_financeiras', {
          'id': '${vendaId}_estorno_$index',
          'tipo': 'estorno',
          'descricao': 'Estorno da venda $vendaId',
          'valor': -((finance['valor'] as num?)?.toDouble() ?? 0),
          'forma_pagamento': finance['forma_pagamento'],
          'status': 'pago',
          'data': now,
          'data_criacao': now,
          'categoria': 'estorno de venda',
          'centro_resultado': 'loja',
          'entidade_origem': 'pdv_venda',
          'entidade_origem_id': vendaId,
          'cliente_id': finance['cliente_id'],
          'profissional_id': finance['profissional_id'],
          'usuario_responsavel_id': u.id,
          'observacoes': motivo.trim(),
        });
      }
      await txn.update(
        'comissoes',
        {'status': 'estornada', 'observacoes': motivo.trim()},
        where: 'id LIKE ?',
        whereArgs: ['${vendaId}_com%'],
      );
    });
  }

  Future<List<Map<String, Object?>>> listarVendas() async {
    final u = _usuario;
    final db = await _databaseProvider();
    return db.rawQuery(
      '''
      SELECT v.id, substr(v.id, 1, 8) numero, v.valor_total total,
        v.status, v.data_venda criada_em, c.nome cliente_nome,
        GROUP_CONCAT(COALESCE(e.nome,p.nome,vi.produto_id),' ') produtos,
        GROUP_CONCAT(COALESCE(e.codigo_barras,e.codigo_interno,p.codigo_exclusivo,vi.produto_id),' ') codigos
      FROM pdv_vendas v
      LEFT JOIN clientes c ON c.id=v.cliente_id
      LEFT JOIN pdv_venda_itens vi ON vi.pdv_venda_id=v.id
      LEFT JOIN estoque e ON e.id=vi.produto_id
      LEFT JOIN pecas_unicas p ON p.id=vi.produto_id
      WHERE v.comercio_id = ?
      GROUP BY v.id
      ORDER BY v.data_venda DESC
    ''',
      [u.comercioId],
    );
  }

  Future<Map<String, Object?>> detalheVenda(String vendaId) async {
    final user = _usuario;
    final db = await _databaseProvider();
    final sales = await db.rawQuery(
      '''SELECT v.*, c.nome cliente_nome, p.nome profissional_nome
      FROM pdv_vendas v LEFT JOIN clientes c ON c.id=v.cliente_id
      LEFT JOIN profissionais p ON p.id=v.profissional_id
      WHERE v.id=? AND v.comercio_id=? LIMIT 1''',
      [vendaId, user.comercioId],
    );
    if (sales.isEmpty) throw StateError('Venda não encontrada.');
    final items = await db.rawQuery(
      '''SELECT vi.*, COALESCE(e.nome,p.nome,vi.produto_id) nome,
      COALESCE(e.codigo_barras,e.codigo_interno,p.codigo_exclusivo) codigo
      FROM pdv_venda_itens vi LEFT JOIN estoque e ON e.id=vi.produto_id
      LEFT JOIN pecas_unicas p ON p.id=vi.produto_id
      WHERE vi.pdv_venda_id=?''',
      [vendaId],
    );
    final payments = await db.query(
      'movimentacoes_financeiras',
      where: 'id LIKE ?',
      whereArgs: ['$vendaId%'],
      orderBy: 'data',
    );
    return {...sales.single, 'itens': items, 'pagamentos': payments};
  }

  Future<void> _sincronizarReposicaoTxn(
    Transaction txn,
    String produtoId,
  ) async {
    final u = _usuario;
    final maps = await txn.query(
      'estoque',
      where:
          "id = ? AND comercio_id = ? AND ativo = 1 AND (tipo_produto = 'venda' OR tipo_produto = 'ambos' OR estoque_destino = 'loja')",
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
      WHERE r.comercio_id = ? AND (e.tipo_produto = 'venda' OR e.tipo_produto = 'ambos' OR e.estoque_destino = 'loja') ORDER BY r.atualizado_em DESC''',
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
