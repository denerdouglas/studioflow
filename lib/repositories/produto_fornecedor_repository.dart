import 'package:sqflite/sqflite.dart';

import '../database/database_service.dart';
import '../models/domain/acesso.dart';
import '../services/session_controller.dart';

class ProdutoFornecedorRepository {
  final Future<Database> Function() _databaseProvider;
  ProdutoFornecedorRepository({Future<Database> Function()? databaseProvider})
    : _databaseProvider =
          databaseProvider ?? (() => DatabaseService.instance.database);

  String get _comercioId {
    final usuario = SessionController.instance.usuario;
    if (usuario == null || !usuario.podeAcao(AcaoPermissao.visualizarEstoque)) {
      throw StateError('Você não possui permissão para visualizar estoque.');
    }
    return usuario.comercioId;
  }

  void _exigirEdicao() {
    if (SessionController.instance.usuario?.podeAcao(
          AcaoPermissao.cadastrarFornecedor,
        ) !=
        true) {
      throw StateError('Você não possui permissão para cadastrar fornecedor.');
    }
  }

  Future<void> salvar({
    required String produtoId,
    required String fornecedorId,
    String? codigoFornecedor,
    required double preco,
    required double quantidadeEmbalagem,
    required int prazoDias,
    String? link,
    String? observacao,
  }) async {
    _exigirEdicao();
    if (preco < 0 || quantidadeEmbalagem <= 0 || prazoDias < 0) {
      throw StateError('Condições do fornecedor inválidas.');
    }
    final db = await _databaseProvider();
    final produto = await db.query(
      'estoque',
      columns: ['id'],
      where: "id=? AND comercio_id=? AND estoque_destino = 'loja'",
      whereArgs: [produtoId, _comercioId],
      limit: 1,
    );
    final fornecedor = await db.query(
      'fornecedores',
      columns: ['id'],
      where: "id=? AND comercio_id=?",
      whereArgs: [fornecedorId, _comercioId],
      limit: 1,
    );
    if (produto.isEmpty || fornecedor.isEmpty) {
      throw StateError('Produto ou fornecedor não pertence ao comércio atual.');
    }
    await db.insert('produto_fornecedores', {
      'produto_id': produtoId,
      'fornecedor_id': fornecedorId,
      'comercio_id': _comercioId,
      'codigo_fornecedor': codigoFornecedor,
      'preco_recente': preco,
      'quantidade_embalagem': quantidadeEmbalagem,
      'prazo_dias': prazoDias,
      'link': link,
      'atualizado_em': DateTime.now().toIso8601String(),
      'observacoes': observacao,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> listar({String? produtoId}) async {
    final db = await _databaseProvider();
    return db.rawQuery(
      '''SELECT pf.*, e.nome produto_nome, f.nome fornecedor_nome
      FROM produto_fornecedores pf
      JOIN estoque e ON e.id=pf.produto_id
      JOIN fornecedores f ON f.id=pf.fornecedor_id
      WHERE pf.comercio_id=? ${produtoId == null ? '' : 'AND pf.produto_id=?'}
      ORDER BY e.nome, pf.preco_recente''',
      produtoId == null ? [_comercioId] : [_comercioId, produtoId],
    );
  }

  Future<void> excluir(String produtoId, String fornecedorId) async {
    _exigirEdicao();
    final db = await _databaseProvider();
    await db.delete(
      'produto_fornecedores',
      where: 'produto_id=? AND fornecedor_id=? AND comercio_id=?',
      whereArgs: [produtoId, fornecedorId, _comercioId],
    );
  }
}
