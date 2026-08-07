import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/utils/id_generator.dart';
import '../database/database_service.dart';
import '../models/domain/acesso.dart';
import '../models/domain/catalogo_loja.dart';
import '../services/session_controller.dart';

class CatalogoLojaRepository {
  final Future<Database> Function() _databaseProvider;

  CatalogoLojaRepository({Future<Database> Function()? databaseProvider})
    : _databaseProvider =
          databaseProvider ?? (() => DatabaseService.instance.database);

  UsuarioAcesso _require(AcaoPermissao action) {
    final user = SessionController.instance.usuario;
    if (user == null ||
        !user.pode(ModuloPermissao.lojaSalao) ||
        !user.podeAcao(action)) {
      throw StateError('Ação não autorizada para os catálogos da Loja.');
    }
    return user;
  }

  Future<List<Map<String, Object?>>> unidades() async {
    final user = _require(AcaoPermissao.visualizarEstoque);
    final db = await _databaseProvider();
    return db.query(
      'unidades',
      columns: ['id', 'nome'],
      where: 'comercio_id = ? AND ativo = 1',
      whereArgs: [user.comercioId],
      orderBy: 'principal DESC, nome COLLATE NOCASE',
    );
  }

  Future<List<CatalogoLoja>> listar({
    String? unidadeId,
    bool incluirInativos = true,
  }) async {
    final user = _require(AcaoPermissao.visualizarEstoque);
    final db = await _databaseProvider();
    final where = <String>['comercio_id = ?'];
    final args = <Object?>[user.comercioId];
    if (unidadeId != null) {
      where.add('(unidade_id = ? OR unidade_id IS NULL)');
      args.add(unidadeId);
    }
    if (!incluirInativos) where.add('ativo = 1');
    final rows = await db.query(
      'catalogos_loja',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'ativo DESC, ordem, nome COLLATE NOCASE',
    );
    return rows.map(CatalogoLoja.fromMap).toList();
  }

  Future<CatalogoLoja?> buscar(String id) async {
    final user = _require(AcaoPermissao.visualizarEstoque);
    final db = await _databaseProvider();
    final rows = await db.query(
      'catalogos_loja',
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [id, user.comercioId],
      limit: 1,
    );
    return rows.isEmpty ? null : CatalogoLoja.fromMap(rows.single);
  }

  Future<String> criar({
    required String nome,
    String? descricao,
    String? imagemCapa,
    String? icone,
    String? unidadeId,
    required TipoControleCatalogo tipoControle,
    bool ativo = true,
  }) async {
    final user = _require(AcaoPermissao.cadastrarProduto);
    if (nome.trim().isEmpty) throw StateError('Informe o nome do catálogo.');
    final db = await _databaseProvider();
    final now = DateTime.now().toUtc();
    final id = IdGenerator.temporal();
    await db.transaction((tx) async {
      final order =
          Sqflite.firstIntValue(
            await tx.rawQuery(
              'SELECT COALESCE(MAX(ordem),-1)+1 FROM catalogos_loja WHERE comercio_id = ?',
              [user.comercioId],
            ),
          ) ??
          0;
      final catalog = CatalogoLoja(
        id: id,
        comercioId: user.comercioId,
        unidadeId: unidadeId ?? SessionController.instance.unidadeAtiva,
        nome: nome.trim(),
        descricao: descricao,
        imagemCapa: imagemCapa,
        icone: icone,
        tipoControle: tipoControle,
        ativo: ativo,
        ordem: order,
        criadoEm: now,
        atualizadoEm: now,
      );
      await tx.insert('catalogos_loja', catalog.toMap());
      await _audit(tx, user, id, null, 'criar_catalogo', null, catalog.toMap());
      await _sync(tx, user, 'catalogo_loja', id, 'upsert', catalog.toMap());
    });
    return id;
  }

  Future<void> editar(CatalogoLoja catalog) async {
    final user = _require(AcaoPermissao.editarProduto);
    if (catalog.comercioId != user.comercioId || catalog.nome.trim().isEmpty) {
      throw StateError('Catálogo inválido.');
    }
    final db = await _databaseProvider();
    await db.transaction((tx) async {
      final previous = await _catalog(tx, user.comercioId, catalog.id);
      final changed = await tx.update(
        'catalogos_loja',
        catalog.toMap()..remove('criado_em'),
        where: 'id = ? AND comercio_id = ?',
        whereArgs: [catalog.id, user.comercioId],
      );
      if (changed == 0) throw StateError('Catálogo não encontrado.');
      await _audit(
        tx,
        user,
        catalog.id,
        null,
        'editar_catalogo',
        previous,
        catalog.toMap(),
      );
      await _sync(
        tx,
        user,
        'catalogo_loja',
        catalog.id,
        'upsert',
        catalog.toMap(),
      );
    });
  }

  Future<void> alterarStatus(String id, bool active) async {
    final catalog = await buscar(id);
    if (catalog == null) throw StateError('Catálogo não encontrado.');
    await editar(catalog.copiarCom(ativo: active));
  }

  Future<void> ordenar(String id, int order) async {
    final catalog = await buscar(id);
    if (catalog == null) throw StateError('Catálogo não encontrado.');
    await editar(catalog.copiarCom(ordem: order.clamp(0, 9999)));
  }

  Future<void> excluir(String id) async {
    final user = _require(AcaoPermissao.editarProduto);
    final db = await _databaseProvider();
    await db.transaction((tx) async {
      final catalog = await _catalog(tx, user.comercioId, id);
      final products =
          Sqflite.firstIntValue(
            await tx.rawQuery(
              'SELECT COUNT(*) FROM estoque WHERE comercio_id = ? AND catalogo_id = ?',
              [user.comercioId, id],
            ),
          ) ??
          0;
      if (products > 0) {
        throw StateError(
          'Catálogo com produtos ou histórico deve ser apenas inativado.',
        );
      }
      await tx.delete(
        'catalogos_loja',
        where: 'id = ? AND comercio_id = ?',
        whereArgs: [id, user.comercioId],
      );
      await _audit(tx, user, id, null, 'excluir_catalogo', catalog, null);
      await _sync(tx, user, 'catalogo_loja', id, 'delete', catalog);
    });
  }

  Future<List<Map<String, Object?>>> produtos(
    String catalogId, {
    bool incluirInativos = true,
  }) async {
    final user = _require(AcaoPermissao.visualizarEstoque);
    final db = await _databaseProvider();
    final query =
        '''
      SELECT e.*, COALESCE(s.quantidade_atual, e.quantidade_atual) as quantidade_atual, COALESCE(s.estoque_minimo, e.estoque_minimo) as estoque_minimo
      FROM estoque e
      LEFT JOIN estoque_saldos s ON e.id = s.estoque_id AND s.finalidade = 'venda'
      WHERE e.comercio_id = ? AND e.catalogo_id = ? 
      AND (e.tipo_produto = 'venda' OR e.tipo_produto = 'ambos' OR e.estoque_destino = 'loja')
      ${incluirInativos ? '' : ' AND e.ativo = 1'}
      ORDER BY e.ativo DESC, e.nome COLLATE NOCASE
    ''';
    return db.rawQuery(query, [user.comercioId, catalogId]);
  }

  Future<String> adicionarProduto({
    required String catalogoId,
    required String nome,
    String? descricao,
    String? codigo,
    String? fornecedorId,
    required double custo,
    required double preco,
    required double quantidade,
    required double estoqueMinimo,
    String unidade = 'un',
    String? lote,
    DateTime? validade,
    String? tamanho,
    String? cor,
    String? variacao,
  }) async {
    final user = _require(AcaoPermissao.cadastrarProduto);
    if (nome.trim().isEmpty ||
        custo < 0 ||
        preco < 0 ||
        quantidade < 0 ||
        estoqueMinimo < 0) {
      throw StateError('Dados do produto inválidos.');
    }
    final db = await _databaseProvider();
    final id = IdGenerator.temporal();
    await db.transaction((tx) async {
      final catalog = await _catalog(tx, user.comercioId, catalogoId);
      if (catalog['ativo'] != 1) throw StateError('Catálogo inativo.');
      if ((codigo ?? '').trim().isNotEmpty) {
        final duplicate = await tx.query(
          'estoque',
          columns: ['id'],
          where:
              'comercio_id = ? AND (codigo_barras = ? OR codigo_interno = ?)',
          whereArgs: [user.comercioId, codigo!.trim(), codigo.trim()],
          limit: 1,
        );
        if (duplicate.isNotEmpty) throw StateError('Código já cadastrado.');
      }
      final now = DateTime.now().toUtc().toIso8601String();
      final type = catalog['tipo_controle'] as String;
      final map = <String, Object?>{
        'id': id,
        'comercio_id': user.comercioId,
        'catalogo_id': catalogoId,
        'estoque_destino': 'loja',
        'nome': nome.trim(),
        'descricao': descricao?.trim(),
        'categoria': catalog['nome'],
        'tipo': type,
        'tipo_controle': type,
        'modalidade': type == 'produto_consignado' ? 'consignado' : 'proprio',
        'fornecedor_principal_id': fornecedorId,
        'custo_unitario': custo,
        'preco_venda': preco,
        'margem': preco - custo,
        'quantidade_atual': quantidade,
        'estoque_minimo': estoqueMinimo,
        'quantidade_sugerida': 0,
        'unidade': unidade.trim().isEmpty ? 'un' : unidade.trim(),
        'quantidade_embalagem': 1,
        'codigo_barras': codigo?.trim(),
        'codigo_interno': codigo?.trim(),
        'lote': lote?.trim(),
        'data_validade': validade?.toUtc().toIso8601String(),
        'tamanho': tamanho?.trim(),
        'cor': cor?.trim(),
        'variacao': variacao?.trim(),
        'ativo': 1,
        'descontar_automaticamente': 1,
        'origem_catalogo': 'catalogo_personalizado',
        'data_cadastro': now,
        'atualizado_em': now,
      };
      await tx.insert('estoque', map);
      if (type == 'item_individual') {
        if ((codigo ?? '').trim().isEmpty) {
          throw StateError('Item individual exige código único.');
        }
        await tx.insert('pecas_unicas', {
          'id': id,
          'comercio_id': user.comercioId,
          'codigo_exclusivo': codigo!.trim(),
          'nome': nome.trim(),
          'descricao': descricao?.trim(),
          'fornecedor_id': fornecedorId,
          'custo': custo,
          'preco': preco,
          'lote_id': lote,
          'unidade_id': SessionController.instance.unidadeAtiva,
          'status': 'disponivel',
          'data_cadastro': now,
        });
      }
      if (quantidade > 0) {
        await tx.insert('movimentacoes_estoque', {
          'id': IdGenerator.temporal(),
          'comercio_id': user.comercioId,
          'item_estoque_id': id,
          'tipo': 'entradaManual',
          'quantidade': quantidade,
          'quantidade_anterior': 0,
          'quantidade_posterior': quantidade,
          'data': now,
          'motivo': 'Estoque inicial do catálogo ${catalog['nome']}',
          'usuario_responsavel_id': user.id,
          'origem': 'catalogo_loja',
          'referencia_id': catalogoId,
        });
      }
      await _audit(tx, user, catalogoId, id, 'criar_produto', null, map);
      await _sync(tx, user, 'estoque', id, 'upsert', map);
    });
    return id;
  }

  Future<void> editarProduto(String id, Map<String, Object?> values) async {
    final user = _require(AcaoPermissao.editarProduto);
    final allowed = <String>{
      'nome',
      'descricao',
      'catalogo_id',
      'custo_unitario',
      'preco_venda',
      'estoque_minimo',
      'fornecedor_principal_id',
      'codigo_barras',
      'codigo_interno',
      'data_validade',
      'lote',
      'tamanho',
      'cor',
      'variacao',
      'tipo_controle',
      'ativo',
    };
    final sanitized = Map<String, Object?>.fromEntries(
      values.entries.where((entry) => allowed.contains(entry.key)),
    );
    if (sanitized.isEmpty) throw StateError('Nenhuma alteração informada.');
    final db = await _databaseProvider();
    await db.transaction((tx) async {
      final previous = await _product(tx, user.comercioId, id);
      sanitized['atualizado_em'] = DateTime.now().toUtc().toIso8601String();
      final changed = await tx.update(
        'estoque',
        sanitized,
        where:
            "id = ? AND comercio_id = ? AND (tipo_produto = 'venda' OR tipo_produto = 'ambos' OR estoque_destino = 'loja')",
        whereArgs: [id, user.comercioId],
      );
      if (changed == 0) throw StateError('Produto não encontrado.');
      final current = await _product(tx, user.comercioId, id);
      await _audit(
        tx,
        user,
        current['catalogo_id'] as String?,
        id,
        'editar_produto',
        previous,
        current,
      );
      await _sync(tx, user, 'estoque', id, 'upsert', current);
    });
  }

  Future<String> duplicarProduto(String id) async {
    final user = _require(AcaoPermissao.cadastrarProduto);
    final db = await _databaseProvider();
    final product = await _product(db, user.comercioId, id);
    return adicionarProduto(
      catalogoId: product['catalogo_id'] as String,
      nome: '${product['nome']} (cópia)',
      descricao: product['descricao'] as String?,
      fornecedorId: product['fornecedor_principal_id'] as String?,
      custo: (product['custo_unitario'] as num).toDouble(),
      preco: (product['preco_venda'] as num? ?? 0).toDouble(),
      quantidade: 0,
      estoqueMinimo: (product['estoque_minimo'] as num).toDouble(),
      unidade: product['unidade'] as String,
      lote: product['lote'] as String?,
      validade: DateTime.tryParse(product['data_validade'] as String? ?? ''),
      tamanho: product['tamanho'] as String?,
      cor: product['cor'] as String?,
      variacao: product['variacao'] as String?,
    );
  }

  Future<void> alterarStatusProduto(String id, bool active) =>
      editarProduto(id, {'ativo': active ? 1 : 0});

  Future<void> excluirProduto(String id) async {
    final user = _require(AcaoPermissao.editarProduto);
    final db = await _databaseProvider();
    await db.transaction((tx) async {
      final product = await _product(tx, user.comercioId, id);
      if (await _productHasHistory(tx, user.comercioId, id)) {
        throw StateError('Produto com histórico deve ser apenas inativado.');
      }
      await tx.delete(
        'estoque',
        where:
            "id = ? AND comercio_id = ? AND (tipo_produto = 'venda' OR tipo_produto = 'ambos' OR estoque_destino = 'loja')",
        whereArgs: [id, user.comercioId],
      );
      await _audit(
        tx,
        user,
        product['catalogo_id'] as String?,
        id,
        'excluir_produto',
        product,
        null,
      );
      await _sync(tx, user, 'estoque', id, 'delete', product);
    });
  }

  Future<List<String>> importarLote(
    String catalogId,
    List<Map<String, Object?>> rows,
  ) async {
    final ids = <String>[];
    for (final row in rows) {
      ids.add(
        await adicionarProduto(
          catalogoId: catalogId,
          nome: row['nome'] as String? ?? '',
          descricao: row['descricao'] as String?,
          codigo: row['codigo'] as String?,
          fornecedorId: row['fornecedor_id'] as String?,
          custo: (row['custo'] as num? ?? 0).toDouble(),
          preco: (row['preco'] as num? ?? 0).toDouble(),
          quantidade: (row['quantidade'] as num? ?? 0).toDouble(),
          estoqueMinimo: (row['estoque_minimo'] as num? ?? 0).toDouble(),
          unidade: row['unidade'] as String? ?? 'un',
          lote: row['lote'] as String?,
          validade: DateTime.tryParse(row['validade'] as String? ?? ''),
          tamanho: row['tamanho'] as String?,
          cor: row['cor'] as String?,
          variacao: row['variacao'] as String?,
        ),
      );
    }
    return ids;
  }

  Future<bool> _productHasHistory(
    DatabaseExecutor db,
    String commerceId,
    String productId,
  ) async {
    for (final query in <String>[
      'SELECT COUNT(*) FROM movimentacoes_estoque WHERE comercio_id = ? AND item_estoque_id = ?',
      'SELECT COUNT(*) FROM comanda_loja_itens WHERE comercio_id = ? AND produto_id = ?',
      'SELECT COUNT(*) FROM consignacao_itens WHERE comercio_id = ? AND produto_id = ?',
      'SELECT COUNT(*) FROM contas_receber_loja WHERE comercio_id = ? AND produto_id = ?',
    ]) {
      if ((Sqflite.firstIntValue(
                await db.rawQuery(query, [commerceId, productId]),
              ) ??
              0) >
          0) {
        return true;
      }
    }
    final sale =
        Sqflite.firstIntValue(
          await db.rawQuery(
            '''SELECT COUNT(*) FROM pdv_venda_itens i JOIN pdv_vendas v
               ON v.id = i.pdv_venda_id WHERE v.comercio_id = ? AND i.produto_id = ?''',
            [commerceId, productId],
          ),
        ) ??
        0;
    return sale > 0;
  }

  static Future<Map<String, Object?>> _catalog(
    DatabaseExecutor db,
    String commerceId,
    String id,
  ) async {
    final rows = await db.query(
      'catalogos_loja',
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [id, commerceId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Catálogo não encontrado.');
    return rows.single;
  }

  static Future<Map<String, Object?>> _product(
    DatabaseExecutor db,
    String commerceId,
    String id,
  ) async {
    final rows = await db.query(
      'estoque',
      where:
          "id = ? AND comercio_id = ? AND (tipo_produto = 'venda' OR tipo_produto = 'ambos' OR estoque_destino = 'loja')",
      whereArgs: [id, commerceId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Produto não encontrado.');
    return rows.single;
  }

  static Future<void> _audit(
    DatabaseExecutor db,
    UsuarioAcesso user,
    String? catalogId,
    String? productId,
    String action,
    Map<String, Object?>? before,
    Map<String, Object?>? after,
  ) => db.insert('catalogo_loja_auditoria', {
    'id': IdGenerator.temporal(),
    'comercio_id': user.comercioId,
    'unidade_id': SessionController.instance.unidadeAtiva,
    'catalogo_id': catalogId,
    'produto_id': productId,
    'usuario_id': user.id,
    'acao': action,
    'estado_anterior': before == null ? null : jsonEncode(before),
    'estado_novo': after == null ? null : jsonEncode(after),
    'criado_em': DateTime.now().toUtc().toIso8601String(),
  });

  static Future<void> _sync(
    DatabaseExecutor db,
    UsuarioAcesso user,
    String entity,
    String entityId,
    String operation,
    Map<String, Object?> payload,
  ) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('fila_sincronizacao', {
      'id': IdGenerator.temporal(),
      'comercio_id': user.comercioId,
      'unidade_id': SessionController.instance.unidadeAtiva,
      'entidade': entity,
      'entidade_id': entityId,
      'operacao': operation,
      'payload_json': jsonEncode(payload),
      'status': 'pendente',
      'criada_em': now,
      'atualizada_em': now,
    });
  }
}
