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
      final anterior = (produto.first['quantidade_atual'] as num).toDouble();
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
        final anterior = (produtos.first['quantidade_atual'] as num).toDouble();
        if (anterior < restante) {
          throw StateError(
            'Estoque consignado divergente. Ajuste o produto antes de fechar.',
          );
        }
        final posterior = anterior - restante;
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
