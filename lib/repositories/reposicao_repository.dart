import 'package:sqflite/sqflite.dart';

import '../core/utils/id_generator.dart';
import '../database/database_service.dart';
import '../services/session_controller.dart';

class ReposicaoRepository {
  static const statusPermitidos = {
    'rascunho',
    'aguardando_aprovacao',
    'aprovado',
    'enviado',
    'confirmado',
    'em_separacao',
    'em_transporte',
    'recebido_parcialmente',
    'recebido',
    'cancelado',
  };
  final Future<Database> Function() _databaseProvider;
  ReposicaoRepository({Future<Database> Function()? databaseProvider})
    : _databaseProvider =
          databaseProvider ?? (() => DatabaseService.instance.database);
  String get _comercioId => SessionController.instance.usuario!.comercioId;

  Future<void> adicionarManual(String produtoId, double quantidade) async {
    if (quantidade <= 0) throw StateError('Quantidade desejada inválida.');
    final db = await _databaseProvider();
    final produto = await db.query(
      'estoque',
      columns: ['id', 'fornecedor_principal_id', 'custo_unitario'],
      where: "id=? AND comercio_id=? AND estoque_destino = 'loja'",
      whereArgs: [produtoId, _comercioId],
      limit: 1,
    );
    if (produto.isEmpty) throw StateError('Produto não encontrado.');
    final agora = DateTime.now().toIso8601String();
    final existente = await db.query(
      'reposicoes',
      columns: ['id'],
      where:
          "produto_id=? AND comercio_id=? AND status NOT IN ('recebido','cancelado')",
      whereArgs: [produtoId, _comercioId],
      limit: 1,
    );
    if (existente.isNotEmpty) {
      await db.update(
        'reposicoes',
        {
          'quantidade_desejada': quantidade,
          'manual': 1,
          'atualizado_em': agora,
        },
        where: "id=? AND comercio_id=?",
        whereArgs: [existente.first['id'], _comercioId],
      );
      return;
    }
    await db.insert('reposicoes', {
      'id': IdGenerator.temporal(),
      'comercio_id': _comercioId,
      'produto_id': produtoId,
      'quantidade_desejada': quantidade,
      'fornecedor_id': produto.first['fornecedor_principal_id'],
      'custo_estimado': produto.first['custo_unitario'],
      'status': 'rascunho',
      'manual': 1,
      'criado_em': agora,
      'atualizado_em': agora,
    });
  }

  Future<void> atualizar({
    required String id,
    required double quantidade,
    required String status,
    String? fornecedorId,
    String? ofertaId,
    double custo = 0,
    double frete = 0,
    int? prazoDias,
    String? observacoes,
  }) async {
    if (quantidade <= 0 || !statusPermitidos.contains(status)) {
      throw StateError('Dados da reposição inválidos.');
    }
    final db = await _databaseProvider();
    final alterados = await db.update(
      'reposicoes',
      {
        'quantidade_desejada': quantidade,
        'fornecedor_id': fornecedorId,
        'oferta_id': ofertaId,
        'custo_estimado': custo,
        'frete': frete,
        'prazo_dias': prazoDias,
        'observacoes': observacoes,
        'status': status,
        'atualizado_em': DateTime.now().toIso8601String(),
      },
      where:
          "id=? AND comercio_id=? AND produto_id IN ("
          "SELECT id FROM estoque WHERE comercio_id=? AND estoque_destino='loja')",
      whereArgs: [id, _comercioId, _comercioId],
    );
    if (alterados == 0) throw StateError('Reposição não encontrada.');
  }
}
