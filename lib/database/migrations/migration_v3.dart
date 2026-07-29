import 'dart:convert';

import 'package:sqflite/sqflite.dart';

abstract final class MigrationV3 {
  static Future<void> executar(Database db, {required bool criarBackup}) async {
    if (criarBackup) await _backup(db);

    const colunasEstoque = <String, String>{
      'descricao': 'TEXT',
      'marca': 'TEXT',
      'codigo_interno': 'TEXT',
      'modalidade': "TEXT NOT NULL DEFAULT 'proprio'",
      'fornecedor_principal_id': 'TEXT',
      'preco_venda': 'REAL NOT NULL DEFAULT 0',
      'margem': 'REAL NOT NULL DEFAULT 0',
      'quantidade_sugerida': 'REAL NOT NULL DEFAULT 0',
      'quantidade_embalagem': 'REAL NOT NULL DEFAULT 1',
      'lote': 'TEXT',
      'data_entrada': 'TEXT',
      'imagem': 'TEXT',
      'atualizado_em': 'TEXT',
    };
    for (final entry in colunasEstoque.entries) {
      await _adicionarColuna(db, 'estoque', entry.key, entry.value);
    }
    await _adicionarColuna(db, 'movimentacoes_estoque', 'origem', 'TEXT');
    await _adicionarColuna(
      db,
      'movimentacoes_estoque',
      'referencia_id',
      'TEXT',
    );
    await _adicionarColuna(
      db,
      'movimentacoes_estoque',
      'justificativa_negativo',
      'TEXT',
    );

    await db.execute('''CREATE TABLE IF NOT EXISTS fornecedores (
      id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL, nome TEXT NOT NULL,
      nome_fantasia TEXT, razao_social TEXT, documento TEXT, telefone TEXT,
      whatsapp TEXT, email TEXT, endereco TEXT, contato_responsavel TEXT,
      prazo_medio_dias INTEGER NOT NULL DEFAULT 0, formas_pagamento TEXT,
      valor_minimo_pedido REAL NOT NULL DEFAULT 0,
      entrega_disponivel INTEGER NOT NULL DEFAULT 0, regioes_atendidas TEXT,
      observacoes TEXT, ativo INTEGER NOT NULL DEFAULT 1,
      criado_em TEXT NOT NULL, atualizado_em TEXT NOT NULL,
      FOREIGN KEY (comercio_id) REFERENCES comercios(id) ON DELETE CASCADE
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS produto_fornecedores (
      produto_id TEXT NOT NULL, fornecedor_id TEXT NOT NULL,
      comercio_id TEXT NOT NULL, codigo_fornecedor TEXT,
      preco_recente REAL NOT NULL DEFAULT 0,
      quantidade_embalagem REAL NOT NULL DEFAULT 1,
      prazo_dias INTEGER NOT NULL DEFAULT 0, link TEXT,
      atualizado_em TEXT NOT NULL, observacoes TEXT,
      PRIMARY KEY (produto_id, fornecedor_id),
      FOREIGN KEY (produto_id) REFERENCES estoque(id) ON DELETE CASCADE,
      FOREIGN KEY (fornecedor_id) REFERENCES fornecedores(id) ON DELETE CASCADE
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS vendas (
      id TEXT PRIMARY KEY, numero TEXT NOT NULL, comercio_id TEXT NOT NULL,
      cliente_id TEXT, usuario_id TEXT NOT NULL, subtotal REAL NOT NULL,
      desconto REAL NOT NULL DEFAULT 0, total REAL NOT NULL,
      status TEXT NOT NULL, observacoes TEXT, criada_em TEXT NOT NULL,
      cancelada_em TEXT, UNIQUE(comercio_id, numero)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS venda_itens (
      id TEXT PRIMARY KEY, venda_id TEXT NOT NULL, comercio_id TEXT NOT NULL,
      produto_id TEXT NOT NULL, nome_produto TEXT NOT NULL,
      quantidade REAL NOT NULL, preco_unitario REAL NOT NULL,
      desconto REAL NOT NULL DEFAULT 0, total REAL NOT NULL,
      FOREIGN KEY (venda_id) REFERENCES vendas(id) ON DELETE CASCADE,
      FOREIGN KEY (produto_id) REFERENCES estoque(id)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS venda_pagamentos (
      id TEXT PRIMARY KEY, venda_id TEXT NOT NULL, comercio_id TEXT NOT NULL,
      forma TEXT NOT NULL, valor REAL NOT NULL,
      status TEXT NOT NULL DEFAULT 'confirmado_manual',
      FOREIGN KEY (venda_id) REFERENCES vendas(id) ON DELETE CASCADE
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS consignacoes (
      id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL, fornecedor_id TEXT NOT NULL,
      lote_colecao TEXT, recebida_em TEXT NOT NULL, fechamento_previsto TEXT,
      fechada_em TEXT, status TEXT NOT NULL, observacoes TEXT,
      criado_em TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS consignacao_itens (
      id TEXT PRIMARY KEY, consignacao_id TEXT NOT NULL,
      comercio_id TEXT NOT NULL, produto_id TEXT NOT NULL,
      quantidade_recebida REAL NOT NULL,
      quantidade_vendida REAL NOT NULL DEFAULT 0,
      quantidade_devolvida REAL NOT NULL DEFAULT 0,
      valor_repasse REAL NOT NULL, preco_venda REAL NOT NULL,
      percentual_salao REAL NOT NULL DEFAULT 0,
      FOREIGN KEY (consignacao_id) REFERENCES consignacoes(id) ON DELETE CASCADE
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS reposicoes (
      id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL, produto_id TEXT NOT NULL,
      quantidade_desejada REAL NOT NULL, fornecedor_id TEXT, oferta_id TEXT,
      custo_estimado REAL NOT NULL DEFAULT 0, frete REAL NOT NULL DEFAULT 0,
      prazo_dias INTEGER, observacoes TEXT,
      status TEXT NOT NULL DEFAULT 'rascunho', manual INTEGER NOT NULL DEFAULT 0,
      criado_em TEXT NOT NULL, atualizado_em TEXT NOT NULL,
      UNIQUE(comercio_id, produto_id, status)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS ofertas_reposicao (
      id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL, produto_id TEXT,
      titulo TEXT NOT NULL, marca TEXT, imagem TEXT,
      quantidade_embalagem REAL NOT NULL DEFAULT 1, preco REAL NOT NULL,
      frete REAL NOT NULL DEFAULT 0, prazo_dias INTEGER, avaliacao REAL,
      plataforma TEXT NOT NULL, vendedor TEXT, link TEXT,
      habitual INTEGER NOT NULL DEFAULT 0, pesquisada_em TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS ordens_compra (
      id TEXT PRIMARY KEY, numero TEXT NOT NULL, comercio_id TEXT NOT NULL,
      fornecedor_id TEXT, usuario_id TEXT NOT NULL, aprovado_por_id TEXT,
      frete REAL NOT NULL DEFAULT 0, desconto REAL NOT NULL DEFAULT 0,
      total REAL NOT NULL, endereco TEXT, observacoes TEXT,
      status TEXT NOT NULL, criada_em TEXT NOT NULL, atualizado_em TEXT NOT NULL,
      UNIQUE(comercio_id, numero)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS ordem_compra_itens (
      id TEXT PRIMARY KEY, ordem_id TEXT NOT NULL, comercio_id TEXT NOT NULL,
      produto_id TEXT NOT NULL, quantidade REAL NOT NULL,
      quantidade_recebida REAL NOT NULL DEFAULT 0,
      valor_unitario REAL NOT NULL, total REAL NOT NULL,
      FOREIGN KEY (ordem_id) REFERENCES ordens_compra(id) ON DELETE CASCADE
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS ordem_compra_historico (
      id TEXT PRIMARY KEY, ordem_id TEXT NOT NULL, comercio_id TEXT NOT NULL,
      status TEXT NOT NULL, usuario_id TEXT NOT NULL, observacao TEXT,
      data TEXT NOT NULL,
      FOREIGN KEY (ordem_id) REFERENCES ordens_compra(id) ON DELETE CASCADE
    )''');

    await db.execute('''INSERT OR IGNORE INTO reposicoes (
      id, comercio_id, produto_id, quantidade_desejada, fornecedor_id,
      custo_estimado, frete, status, manual, criado_em, atualizado_em
    ) SELECT
      'repo_v3_' || id, comercio_id, id,
      CASE WHEN quantidade_sugerida > 0 THEN quantidade_sugerida
           WHEN (estoque_minimo * 2 - quantidade_atual) > 0
           THEN (estoque_minimo * 2 - quantidade_atual) ELSE 1 END,
      fornecedor_principal_id, custo_unitario, 0, 'rascunho', 0,
      COALESCE(atualizado_em, data_cadastro), COALESCE(atualizado_em, data_cadastro)
    FROM estoque
    WHERE ativo = 1 AND quantidade_atual <= estoque_minimo''');
    for (final sql in <String>[
      'CREATE INDEX IF NOT EXISTS idx_estoque_comercio_codigo ON estoque(comercio_id, codigo_barras)',
      'CREATE INDEX IF NOT EXISTS idx_fornecedores_comercio ON fornecedores(comercio_id, ativo, nome)',
      'CREATE INDEX IF NOT EXISTS idx_vendas_comercio_data ON vendas(comercio_id, criada_em)',
      'CREATE INDEX IF NOT EXISTS idx_mov_estoque_comercio_data ON movimentacoes_estoque(comercio_id, data)',
      'CREATE INDEX IF NOT EXISTS idx_reposicoes_comercio_status ON reposicoes(comercio_id, status)',
      'CREATE INDEX IF NOT EXISTS idx_ordens_comercio_status ON ordens_compra(comercio_id, status)',
    ]) {
      await db.execute(sql);
    }
  }

  static Future<void> _backup(Database db) async {
    final agora = DateTime.now().toUtc().toIso8601String();
    for (final tabela in ['estoque', 'movimentacoes_estoque']) {
      final dados = await db.query(tabela);
      final estrutura = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
        [tabela],
      );
      await db.insert('backups_logicos', {
        'versao_origem': 2,
        'tabela': tabela,
        'estrutura_sql': estrutura.isEmpty ? null : estrutura.first['sql'],
        'dados_json': jsonEncode(dados),
        'criado_em': agora,
      });
    }
  }

  static Future<void> _adicionarColuna(
    Database db,
    String tabela,
    String coluna,
    String definicao,
  ) async {
    final colunas = await db.rawQuery('PRAGMA table_info($tabela)');
    if (!colunas.any((item) => item['name'] == coluna)) {
      await db.execute('ALTER TABLE $tabela ADD COLUMN $coluna $definicao');
    }
  }
}
