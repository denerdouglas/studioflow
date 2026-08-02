import 'package:sqflite/sqflite.dart';

import '../database/database_service.dart';
import '../models/domain/acesso.dart';
import '../services/product_catalog_contribution_service.dart';
import '../services/session_controller.dart';

class ItemEstoqueRegistro {
  final String id;
  final String nome;
  final String categoria;
  final String tipo;
  final double quantidadeAtual;
  final double estoqueMinimo;
  final String unidade;
  final double conteudoPorUnidade;
  final String unidadeConteudo;
  final bool revisaoModelagemEstoque;
  final double custoUnitario;
  final String fornecedor;
  final String codigoBarras;
  final DateTime? dataValidade;
  final bool ativo;
  final bool descontarAutomaticamente;
  final String observacoes;
  final DateTime dataCadastro;

  const ItemEstoqueRegistro({
    required this.id,
    required this.nome,
    required this.categoria,
    required this.tipo,
    required this.quantidadeAtual,
    required this.estoqueMinimo,
    required this.unidade,
    required this.conteudoPorUnidade,
    required this.unidadeConteudo,
    required this.revisaoModelagemEstoque,
    required this.custoUnitario,
    required this.fornecedor,
    required this.codigoBarras,
    required this.dataValidade,
    required this.ativo,
    required this.descontarAutomaticamente,
    required this.observacoes,
    required this.dataCadastro,
  });

  bool get estoqueBaixo {
    return ativo && quantidadeAtual <= estoqueMinimo;
  }

  bool get vencido {
    final validade = dataValidade;

    if (validade == null) {
      return false;
    }

    final hoje = DateTime.now();

    final dataHoje = DateTime(hoje.year, hoje.month, hoje.day);

    final dataProduto = DateTime(validade.year, validade.month, validade.day);

    return dataProduto.isBefore(dataHoje);
  }

  double get valorEmEstoque {
    return quantidadeAtual * custoUnitario;
  }

  Map<String, Object?> paraMapa() {
    return {
      'id': id,
      'nome': nome,
      'categoria': categoria,
      'tipo': tipo,
      'quantidade_atual': quantidadeAtual,
      'estoque_minimo': estoqueMinimo,
      'unidade': unidade,
      'conteudo_por_unidade': conteudoPorUnidade,
      'unidade_conteudo': unidadeConteudo,
      'revisao_modelagem_estoque': revisaoModelagemEstoque ? 1 : 0,
      'custo_unitario': custoUnitario,
      'fornecedor': fornecedor.isEmpty ? null : fornecedor,
      'codigo_barras': codigoBarras.isEmpty ? null : codigoBarras,
      'data_validade': dataValidade?.toIso8601String(),
      'ativo': ativo ? 1 : 0,
      'descontar_automaticamente': descontarAutomaticamente ? 1 : 0,
      'observacoes': observacoes,
      'data_cadastro': dataCadastro.toIso8601String(),
    };
  }

  factory ItemEstoqueRegistro.doMapa(Map<String, Object?> mapa) {
    return ItemEstoqueRegistro(
      id: mapa['id'] as String,
      nome: mapa['nome'] as String? ?? 'Item',
      categoria: mapa['categoria'] as String? ?? 'Outros',
      tipo: mapa['tipo'] as String? ?? 'consumivel',
      quantidadeAtual: (mapa['quantidade_atual'] as num? ?? 0).toDouble(),
      estoqueMinimo: (mapa['estoque_minimo'] as num? ?? 0).toDouble(),
      unidade: mapa['unidade'] as String? ?? 'unidade',
      conteudoPorUnidade: (mapa['conteudo_por_unidade'] as num? ?? 1).toDouble(),
      unidadeConteudo: mapa['unidade_conteudo'] as String? ?? '',
      revisaoModelagemEstoque: (mapa['revisao_modelagem_estoque'] as num? ?? 0) == 1,
      custoUnitario: (mapa['custo_unitario'] as num? ?? 0).toDouble(),
      fornecedor: mapa['fornecedor'] as String? ?? '',
      codigoBarras: mapa['codigo_barras'] as String? ?? '',
      dataValidade: DateTime.tryParse(mapa['data_validade'] as String? ?? ''),
      ativo: (mapa['ativo'] as num? ?? 1) == 1,
      descontarAutomaticamente:
          (mapa['descontar_automaticamente'] as num? ?? 1) == 1,
      observacoes: mapa['observacoes'] as String? ?? '',
      dataCadastro:
          DateTime.tryParse(mapa['data_cadastro'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  ItemEstoqueRegistro copiarCom({
    String? nome,
    String? categoria,
    String? tipo,
    double? quantidadeAtual,
    double? estoqueMinimo,
    String? unidade,
    double? conteudoPorUnidade,
    String? unidadeConteudo,
    bool? revisaoModelagemEstoque,
    double? custoUnitario,
    String? fornecedor,
    String? codigoBarras,
    DateTime? dataValidade,
    bool removerDataValidade = false,
    bool? ativo,
    bool? descontarAutomaticamente,
    String? observacoes,
  }) {
    return ItemEstoqueRegistro(
      id: id,
      nome: nome ?? this.nome,
      categoria: categoria ?? this.categoria,
      tipo: tipo ?? this.tipo,
      quantidadeAtual: quantidadeAtual ?? this.quantidadeAtual,
      estoqueMinimo: estoqueMinimo ?? this.estoqueMinimo,
      unidade: unidade ?? this.unidade,
      conteudoPorUnidade: conteudoPorUnidade ?? this.conteudoPorUnidade,
      unidadeConteudo: unidadeConteudo ?? this.unidadeConteudo,
      revisaoModelagemEstoque: revisaoModelagemEstoque ?? this.revisaoModelagemEstoque,
      custoUnitario: custoUnitario ?? this.custoUnitario,
      fornecedor: fornecedor ?? this.fornecedor,
      codigoBarras: codigoBarras ?? this.codigoBarras,
      dataValidade: removerDataValidade
          ? null
          : dataValidade ?? this.dataValidade,
      ativo: ativo ?? this.ativo,
      descontarAutomaticamente:
          descontarAutomaticamente ?? this.descontarAutomaticamente,
      observacoes: observacoes ?? this.observacoes,
      dataCadastro: dataCadastro,
    );
  }
}

class MovimentacaoEstoqueRegistro {
  final String id;
  final String itemEstoqueId;
  final String tipo;
  final double quantidade;
  final double quantidadeAnterior;
  final double quantidadePosterior;
  final DateTime data;
  final String motivo;
  final String? agendamentoId;
  final String? profissionalId;
  final String? usuarioResponsavelId;

  const MovimentacaoEstoqueRegistro({
    required this.id,
    required this.itemEstoqueId,
    required this.tipo,
    required this.quantidade,
    required this.quantidadeAnterior,
    required this.quantidadePosterior,
    required this.data,
    required this.motivo,
    required this.agendamentoId,
    required this.profissionalId,
    required this.usuarioResponsavelId,
  });

  Map<String, Object?> paraMapa() {
    return {
      'id': id,
      'item_estoque_id': itemEstoqueId,
      'tipo': tipo,
      'quantidade': quantidade,
      'quantidade_anterior': quantidadeAnterior,
      'quantidade_posterior': quantidadePosterior,
      'data': data.toIso8601String(),
      'motivo': motivo,
      'agendamento_id': agendamentoId,
      'profissional_id': profissionalId,
      'usuario_responsavel_id': usuarioResponsavelId,
    };
  }

  factory MovimentacaoEstoqueRegistro.doMapa(Map<String, Object?> mapa) {
    return MovimentacaoEstoqueRegistro(
      id: mapa['id'] as String,
      itemEstoqueId: mapa['item_estoque_id'] as String,
      tipo: mapa['tipo'] as String? ?? 'entrada',
      quantidade: (mapa['quantidade'] as num? ?? 0).toDouble(),
      quantidadeAnterior: (mapa['quantidade_anterior'] as num? ?? 0).toDouble(),
      quantidadePosterior: (mapa['quantidade_posterior'] as num? ?? 0)
          .toDouble(),
      data: DateTime.tryParse(mapa['data'] as String? ?? '') ?? DateTime.now(),
      motivo: mapa['motivo'] as String? ?? '',
      agendamentoId: mapa['agendamento_id'] as String?,
      profissionalId: mapa['profissional_id'] as String?,
      usuarioResponsavelId: mapa['usuario_responsavel_id'] as String?,
    );
  }
}

class ResumoEstoque {
  final int totalItens;
  final int itensAtivos;
  final int itensEstoqueBaixo;
  final int itensVencidos;
  final double valorTotal;

  const ResumoEstoque({
    required this.totalItens,
    required this.itensAtivos,
    required this.itensEstoqueBaixo,
    required this.itensVencidos,
    required this.valorTotal,
  });

  factory ResumoEstoque.vazio() {
    return const ResumoEstoque(
      totalItens: 0,
      itensAtivos: 0,
      itensEstoqueBaixo: 0,
      itensVencidos: 0,
      valorTotal: 0,
    );
  }
}

class EstoqueRepository {
  final DatabaseService _databaseService;

  EstoqueRepository({DatabaseService? databaseService})
    : _databaseService = databaseService ?? DatabaseService.instance;

  String get _comercioId {
    final usuario = SessionController.instance.usuario;
    if (usuario == null || !usuario.podeAcao(AcaoPermissao.visualizarEstoque)) {
      throw StateError('Você não possui permissão para visualizar estoque.');
    }
    return usuario.comercioId;
  }

  void _exigirAcao(AcaoPermissao acao) {
    final usuario = SessionController.instance.usuario;
    if (usuario == null || !usuario.podeAcao(acao)) {
      throw StateError(
        'Você não possui permissão para ${acao.nome.toLowerCase()}.',
      );
    }
  }

  ItemEstoqueRegistro _aplicarVisibilidade(ItemEstoqueRegistro item) {
    final podeVerCusto =
        SessionController.instance.usuario?.podeAcao(
          AcaoPermissao.visualizarCusto,
        ) ??
        false;
    return podeVerCusto ? item : item.copiarCom(custoUnitario: 0);
  }

  Future<List<ItemEstoqueRegistro>> listar({
    bool incluirInativos = true,
  }) async {
    final Database db = await _databaseService.database;

    final registros = await db.query(
      'estoque',
      where: incluirInativos
          ? "comercio_id = ? AND estoque_destino = 'salao'"
          : "ativo = ? AND comercio_id = ? AND estoque_destino = 'salao'",
      whereArgs: incluirInativos ? [_comercioId] : [1, _comercioId],
      orderBy: 'ativo DESC, nome COLLATE NOCASE ASC',
    );

    return registros
        .map(ItemEstoqueRegistro.doMapa)
        .map(_aplicarVisibilidade)
        .toList();
  }

  Future<List<ItemEstoqueRegistro>> listarEstoqueBaixo() async {
    final Database db = await _databaseService.database;

    final registros = await db.query(
      'estoque',
      where: '''
        ativo = ?
        AND quantidade_atual <= estoque_minimo
        AND comercio_id = ?
        AND estoque_destino = 'salao'
      ''',
      whereArgs: [1, _comercioId],
      orderBy: 'quantidade_atual ASC',
    );

    return registros
        .map(ItemEstoqueRegistro.doMapa)
        .map(_aplicarVisibilidade)
        .toList();
  }

  Future<ItemEstoqueRegistro?> buscarPorId(String id) async {
    final Database db = await _databaseService.database;

    final registros = await db.query(
      'estoque',
      where: "id = ? AND comercio_id = ? AND estoque_destino = 'salao'",
      whereArgs: [id, _comercioId],
      limit: 1,
    );

    if (registros.isEmpty) {
      return null;
    }

    return _aplicarVisibilidade(ItemEstoqueRegistro.doMapa(registros.first));
  }

  Future<void> inserir(ItemEstoqueRegistro item) async {
    _exigirAcao(AcaoPermissao.cadastrarProduto);
    final Database db = await _databaseService.database;

    final user = SessionController.instance.usuario!;
    await db.transaction((txn) async {
      await txn.insert('estoque', {
        ...item.paraMapa(),
        'comercio_id': _comercioId,
        'estoque_destino': 'salao',
        'origem_catalogo': 'manual',
      }, conflictAlgorithm: ConflictAlgorithm.abort);
      await ProductCatalogContributionService.enqueue(
        txn,
        user: user,
        barcode: item.codigoBarras.trim(),
        name: item.nome,
        category: item.categoria,
        unit: item.unidade,
      );
    });
  }

  Future<void> atualizar(ItemEstoqueRegistro item) async {
    _exigirAcao(AcaoPermissao.editarProduto);
    final Database db = await _databaseService.database;

    final quantidadeAlterada = await db.update(
      'estoque',
      item.paraMapa(),
      where: "id = ? AND comercio_id = ? AND estoque_destino = 'salao'",
      whereArgs: [item.id, _comercioId],
    );

    if (quantidadeAlterada == 0) {
      throw StateError('Item de estoque não encontrado.');
    }
  }

  Future<void> salvar(ItemEstoqueRegistro item) async {
    final existente = await buscarPorId(item.id);

    if (existente == null) {
      await inserir(item);
      return;
    }

    await atualizar(item);
  }

  Future<void> alterarStatus({required String id, required bool ativo}) async {
    _exigirAcao(AcaoPermissao.editarProduto);
    final Database db = await _databaseService.database;

    await db.update(
      'estoque',
      {'ativo': ativo ? 1 : 0},
      where: "id = ? AND comercio_id = ? AND estoque_destino = 'salao'",
      whereArgs: [id, _comercioId],
    );
  }

  Future<void> desativar(String id) async {
    await alterarStatus(id: id, ativo: false);
  }

  Future<void> reativar(String id) async {
    await alterarStatus(id: id, ativo: true);
  }

  Future<void> registrarMovimentacao({
    required String itemId,
    required String tipo,
    required double quantidade,
    required String motivo,
    String? agendamentoId,
    String? profissionalId,
    String? usuarioResponsavelId,
  }) async {
    _exigirAcao(AcaoPermissao.movimentarEstoque);
    if (quantidade <= 0) {
      throw StateError('A quantidade deve ser maior que zero.');
    }

    final Database db = await _databaseService.database;

    await db.transaction((transaction) async {
      final registros = await transaction.query(
        'estoque',
        where: "id = ? AND comercio_id = ? AND estoque_destino = 'salao'",
        whereArgs: [itemId, _comercioId],
        limit: 1,
      );

      if (registros.isEmpty) {
        throw StateError('Item de estoque não encontrado.');
      }

      final item = ItemEstoqueRegistro.doMapa(registros.first);

      final quantidadeAnterior = item.quantidadeAtual;

      double quantidadePosterior;

      if (tipo == 'entrada') {
        quantidadePosterior = quantidadeAnterior + quantidade;
      } else if (tipo == 'saida') {
        quantidadePosterior = quantidadeAnterior - quantidade;

        if (quantidadePosterior < 0) {
          throw StateError('A saída é maior que a quantidade disponível.');
        }
      } else if (tipo == 'ajuste') {
        quantidadePosterior = quantidade;
      } else {
        throw StateError('Tipo de movimentação inválido.');
      }

      final agora = DateTime.now();

      await transaction.update(
        'estoque',
        {'quantidade_atual': quantidadePosterior},
        where: "id = ? AND comercio_id = ? AND estoque_destino = 'salao'",
        whereArgs: [itemId, _comercioId],
      );

      final movimentacao = MovimentacaoEstoqueRegistro(
        id: agora.microsecondsSinceEpoch.toString(),
        itemEstoqueId: itemId,
        tipo: tipo,
        quantidade: quantidade,
        quantidadeAnterior: quantidadeAnterior,
        quantidadePosterior: quantidadePosterior,
        data: agora,
        motivo: motivo,
        agendamentoId: agendamentoId,
        profissionalId: profissionalId,
        usuarioResponsavelId: usuarioResponsavelId,
      );

      await transaction.insert('movimentacoes_estoque', {
        ...movimentacao.paraMapa(),
        'comercio_id': _comercioId,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
    });
  }

  Future<void> registrarEntrada({
    required String itemId,
    required double quantidade,
    required String motivo,
  }) async {
    await registrarMovimentacao(
      itemId: itemId,
      tipo: 'entrada',
      quantidade: quantidade,
      motivo: motivo,
    );
  }

  Future<void> registrarSaida({
    required String itemId,
    required double quantidade,
    required String motivo,
    String? agendamentoId,
    String? profissionalId,
  }) async {
    await registrarMovimentacao(
      itemId: itemId,
      tipo: 'saida',
      quantidade: quantidade,
      motivo: motivo,
      agendamentoId: agendamentoId,
      profissionalId: profissionalId,
    );
  }

  Future<void> ajustarQuantidade({
    required String itemId,
    required double novaQuantidade,
    required String motivo,
  }) async {
    await registrarMovimentacao(
      itemId: itemId,
      tipo: 'ajuste',
      quantidade: novaQuantidade,
      motivo: motivo,
    );
  }

  Future<List<MovimentacaoEstoqueRegistro>> listarMovimentacoes({
    String? itemId,
    int limite = 100,
  }) async {
    final Database db = await _databaseService.database;

    final registros = await db.query(
      'movimentacoes_estoque',
      where: itemId == null
          ? 'comercio_id = ?'
          : 'item_estoque_id = ? AND comercio_id = ?',
      whereArgs: itemId == null ? [_comercioId] : [itemId, _comercioId],
      orderBy: 'data DESC',
      limit: limite,
    );

    return registros.map(MovimentacaoEstoqueRegistro.doMapa).toList();
  }

  Future<ResumoEstoque> resumo() async {
    final itens = await listar();

    int ativos = 0;
    int estoqueBaixo = 0;
    int vencidos = 0;
    double valorTotal = 0;

    for (final item in itens) {
      if (item.ativo) {
        ativos++;
        valorTotal += item.valorEmEstoque;

        if (item.estoqueBaixo) {
          estoqueBaixo++;
        }

        if (item.vencido) {
          vencidos++;
        }
      }
    }

    return ResumoEstoque(
      totalItens: itens.length,
      itensAtivos: ativos,
      itensEstoqueBaixo: estoqueBaixo,
      itensVencidos: vencidos,
      valorTotal: valorTotal,
    );
  }

  Future<bool> existeNome({required String nome, String? ignorarId}) async {
    final Database db = await _databaseService.database;

    String where =
        "comercio_id = ? AND estoque_destino = 'salao' "
        'AND LOWER(TRIM(nome)) = LOWER(TRIM(?))';

    final argumentos = <Object?>[_comercioId, nome];

    if (ignorarId != null) {
      where += ' AND id != ?';
      argumentos.add(ignorarId);
    }

    final registros = await db.query(
      'estoque',
      columns: ['id'],
      where: where,
      whereArgs: argumentos,
      limit: 1,
    );

    return registros.isNotEmpty;
  }
}
