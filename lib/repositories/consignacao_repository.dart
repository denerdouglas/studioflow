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
    String? unidadeId,
    DateTime? recolhimentoPrevisto,
    int? prazoCobrancaDias,
    required List<Map<String, Object?>> pecas,
  }) async {
    final user = _usuario;
    if (nomeLote.trim().isEmpty || pecas.isEmpty) {
      throw StateError('Informe a maleta e as peças.');
    }
    final db = await _databaseProvider();
    final id = IdGenerator.temporal();
    await db.transaction((tx) async {
      final now = DateTime.now().toUtc().toIso8601String();
      await tx.insert('consignacoes', {
        'id': id,
        'comercio_id': user.comercioId,
        'fornecedor_id': fornecedorId,
        'lote_colecao': nomeLote.trim(),
        'nome_lote': nomeLote.trim(),
        'codigo_referencia': id,
        'unidade_id': unidadeId,
        'recebida_em': now,
        'data_prevista_recolhimento': recolhimentoPrevisto?.toIso8601String(),
        'prazo_cobranca_dias': prazoCobrancaDias,
        'status': 'aberta',
        'criado_em': now,
        'quantidade_recebida': pecas.length,
        'quantidade_disponivel': pecas.length,
      });
      for (final piece in pecas) {
        final code = (piece['codigo'] as String?)?.trim();
        final name = (piece['nome'] as String?)?.trim();
        final price = (piece['preco'] as num?)?.toDouble();
        if (code == null ||
            code.isEmpty ||
            name == null ||
            name.isEmpty ||
            price == null ||
            price < 0) {
          throw StateError('Peça consignada inválida.');
        }
        final pieceId = IdGenerator.temporal();
        await tx.insert('pecas_unicas', {
          'id': pieceId,
          'comercio_id': user.comercioId,
          'codigo_exclusivo': code,
          'nome': name,
          'descricao': piece['descricao'],
          'material': piece['material'],
          'marca': piece['marca'],
          'fornecedor_id': fornecedorId,
          'custo': (piece['repasse'] as num?)?.toDouble() ?? 0,
          'preco': price,
          'lote_id': id,
          'unidade_id': unidadeId,
          'status': 'disponivel',
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
    });
    return id;
  }

  Future<void> venderPeca(
    String pecaId, {
    required String clienteId,
    String? profissionalId,
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
        'valor': piece['preco'],
        'cliente_id': clienteId,
        'profissional_id': profissionalId,
        'criado_em': now,
      });
      await tx.rawUpdate(
        '''UPDATE consignacoes SET quantidade_vendida=quantidade_vendida+1,
        quantidade_disponivel=quantidade_disponivel-1, valor_vendido=valor_vendido+?
        WHERE id=? AND comercio_id=?''',
        [piece['preco'], piece['lote_id'], user.comercioId],
      );
    });
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

  Future<List<Map<String, Object?>>> pecas(String loteId) async {
    final user = _usuario;
    final db = await _databaseProvider();
    return db.query(
      'pecas_unicas',
      where: 'lote_id=? AND comercio_id=?',
      whereArgs: [loteId, user.comercioId],
      orderBy: 'codigo_exclusivo',
    );
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
}
