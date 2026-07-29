import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// Migração comercial v6. Todas as alterações são aditivas e idempotentes.
abstract final class MigrationV6 {
  static Future<void> executar(Database db, {required bool criarBackup}) async {
    if (criarBackup) await _backup(db);

    await _adicionarColuna(
      db,
      'estoque',
      'estoque_destino',
      "TEXT NOT NULL DEFAULT 'salao'",
    );
    // Registros anteriores à v3 nasceram no estoque operacional. Campos de
    // venda preenchidos identificam com segurança os itens da Loja do Salão.
    await db.execute('''UPDATE estoque SET estoque_destino = 'loja'
      WHERE estoque_destino = 'salao' AND (
        COALESCE(codigo_interno, '') <> '' OR COALESCE(preco_venda, 0) > 0 OR
        modalidade = 'consignado' OR fornecedor_principal_id IS NOT NULL
      )''');

    for (final sql in _tabelas) {
      await db.execute(sql);
    }
    for (final sql in _indices) {
      await db.execute(sql);
    }

    final agora = DateTime.now().toUtc().toIso8601String();
    await db.rawInsert(
      '''INSERT OR IGNORE INTO assinaturas
      (id, comercio_id, plano, status, inicio_trial, fim_trial, valor_mensal,
       moeda, provedor, criado_em, atualizado_em)
      SELECT 'sub_' || id, id, 'unico', 'trial', ?, ?, 24.99, 'BRL', 'mock', ?, ?
      FROM comercios''',
      [
        agora,
        DateTime.now().toUtc().add(const Duration(days: 30)).toIso8601String(),
        agora,
        agora,
      ],
    );
    await db.rawInsert(
      '''INSERT OR IGNORE INTO progresso_configuracao
      (comercio_id, etapa, concluida, atualizado_em)
      SELECT c.id, e.etapa, 0, ? FROM comercios c CROSS JOIN (
        SELECT 'dados_negocio' etapa UNION ALL SELECT 'horarios' UNION ALL
        SELECT 'logomarca' UNION ALL SELECT 'profissionais' UNION ALL
        SELECT 'servicos' UNION ALL SELECT 'horarios' UNION ALL SELECT 'agenda' UNION ALL
        SELECT 'clientes' UNION ALL SELECT 'estoque_salao' UNION ALL
        SELECT 'loja_salao' UNION ALL SELECT 'estoque_loja' UNION ALL
        SELECT 'fornecedores' UNION ALL SELECT 'cardapio' UNION ALL
        SELECT 'ia' UNION ALL SELECT 'pagamentos' UNION ALL SELECT 'assinatura'
      ) e''',
      [agora],
    );
    for (final flag in _flags.entries) {
      await db.insert('feature_flags', {
        'chave': flag.key,
        'habilitada': flag.value ? 1 : 0,
        'descricao': _descricaoFlag(flag.key),
        'atualizado_em': agora,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  static const _flags = <String, bool>{
    'shared_product_catalog': true,
    'community_catalog': true,
    'subscription_mock': true,
    'salon_menu': true,
    'customer_profile': false,
    'customer_area': false,
    'nearby_salons': false,
    'whatsapp_official': false,
    'online_ai': false,
    'catalog_ocr': false,
    'cloud_sync': false,
  };

  static String _descricaoFlag(String chave) => switch (chave) {
    'customer_profile' => 'Perfil do cliente reservado para backend seguro',
    'customer_area' => 'Área do cliente ainda não publicada',
    'nearby_salons' => 'Busca geográfica requer consentimento e backend',
    'whatsapp_official' => 'Integração oficial requer backend e credenciais',
    'online_ai' => 'IA online requer backend seguro',
    'catalog_ocr' => 'OCR real requer provedor externo',
    'cloud_sync' => 'Sincronização remota ainda não configurada',
    _ => 'Funcionalidade StudioFlow v6',
  };

  static const _tabelas = <String>[
    '''CREATE TABLE IF NOT EXISTS catalogo_produtos (
      gtin TEXT PRIMARY KEY, global_product_id TEXT UNIQUE, ean TEXT, upc TEXT,
      barcode TEXT, nome TEXT NOT NULL, nome_oficial TEXT, marca TEXT, fabricante TEXT,
      descricao TEXT, categoria TEXT, subcategoria TEXT, unidade TEXT, peso TEXT,
      volume TEXT, quantidade_embalagem REAL, tamanho TEXT, cor TEXT, sabor TEXT,
      fragrancia TEXT, modelo TEXT, variante TEXT, imagem_url TEXT, pais_origem TEXT,
      fonte TEXT NOT NULL, nivel_confianca TEXT NOT NULL DEFAULT 'pending',
      confianca REAL NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'ativo',
      criado_em TEXT NOT NULL, atualizado_em TEXT NOT NULL
    )''',
    '''CREATE TABLE IF NOT EXISTS catalogo_variacoes (
      gtin TEXT PRIMARY KEY, produto_base_gtin TEXT, nome_variacao TEXT,
      atributos_json TEXT NOT NULL DEFAULT '{}', criado_em TEXT NOT NULL,
      FOREIGN KEY (produto_base_gtin) REFERENCES catalogo_produtos(gtin)
    )''',
    '''CREATE TABLE IF NOT EXISTS catalogo_cache (
      gtin TEXT PRIMARY KEY, dados_json TEXT NOT NULL, fonte TEXT NOT NULL,
      expira_em TEXT NOT NULL, atualizado_em TEXT NOT NULL
    )''',
    '''CREATE TABLE IF NOT EXISTS catalogo_sugestoes (
      id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL, usuario_id TEXT NOT NULL,
      gtin TEXT NOT NULL, dados_json TEXT NOT NULL, campo TEXT, valor_anterior TEXT, valor_sugerido TEXT,
      motivo TEXT, fonte_informada TEXT, consentimento INTEGER NOT NULL,
      status TEXT NOT NULL DEFAULT 'pendente', observacao_moderacao TEXT,
      criado_em TEXT NOT NULL, moderado_em TEXT, moderado_por_id TEXT,
      FOREIGN KEY (comercio_id) REFERENCES comercios(id) ON DELETE CASCADE,
      FOREIGN KEY (usuario_id) REFERENCES usuarios(id) ON DELETE CASCADE
    )''',
    '''CREATE TABLE IF NOT EXISTS catalogo_auditoria (
      id TEXT PRIMARY KEY, sugestao_id TEXT, gtin TEXT NOT NULL, acao TEXT NOT NULL,
      usuario_id TEXT, detalhes_json TEXT NOT NULL DEFAULT '{}', criado_em TEXT NOT NULL
    )''',
    '''CREATE TABLE IF NOT EXISTS assinaturas (
      id TEXT UNIQUE, comercio_id TEXT PRIMARY KEY, plano TEXT NOT NULL DEFAULT 'unico',
      status TEXT NOT NULL DEFAULT 'trial', inicio_trial TEXT NOT NULL,
      fim_trial TEXT NOT NULL, valor_mensal REAL NOT NULL DEFAULT 24.99,
      moeda TEXT NOT NULL DEFAULT 'BRL', provedor TEXT NOT NULL DEFAULT 'mock',
      referencia_externa TEXT, periodo_atual_fim TEXT, criado_em TEXT NOT NULL,
      atualizado_em TEXT NOT NULL,
      FOREIGN KEY (comercio_id) REFERENCES comercios(id) ON DELETE CASCADE
    )''',
    '''CREATE TABLE IF NOT EXISTS assinatura_eventos (
      id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL, status_anterior TEXT,
      status_novo TEXT NOT NULL, motivo TEXT, provedor TEXT NOT NULL,
      criado_em TEXT NOT NULL,
      FOREIGN KEY (comercio_id) REFERENCES comercios(id) ON DELETE CASCADE
    )''',
    '''CREATE TABLE IF NOT EXISTS progresso_configuracao (
      comercio_id TEXT NOT NULL, etapa TEXT NOT NULL,
      concluida INTEGER NOT NULL DEFAULT 0, atualizado_em TEXT NOT NULL,
      PRIMARY KEY (comercio_id, etapa),
      FOREIGN KEY (comercio_id) REFERENCES comercios(id) ON DELETE CASCADE
    )''',
    '''CREATE TABLE IF NOT EXISTS feature_flags (
      chave TEXT PRIMARY KEY, habilitada INTEGER NOT NULL DEFAULT 0,
      descricao TEXT NOT NULL, atualizado_em TEXT NOT NULL
    )''',
    '''CREATE TABLE IF NOT EXISTS cardapio_itens (
      id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL, nome TEXT NOT NULL,
      descricao TEXT, preco REAL NOT NULL DEFAULT 0, categoria TEXT,
      imagem TEXT, ativo INTEGER NOT NULL DEFAULT 1, criado_em TEXT NOT NULL,
      atualizado_em TEXT NOT NULL,
      FOREIGN KEY (comercio_id) REFERENCES comercios(id) ON DELETE CASCADE
    )''',
    '''CREATE TABLE IF NOT EXISTS cardapio_complementos (
      id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL, item_id TEXT NOT NULL,
      nome TEXT NOT NULL, preco_adicional REAL NOT NULL DEFAULT 0,
      ativo INTEGER NOT NULL DEFAULT 1,
      FOREIGN KEY (comercio_id) REFERENCES comercios(id) ON DELETE CASCADE,
      FOREIGN KEY (item_id) REFERENCES cardapio_itens(id) ON DELETE CASCADE
    )''',
    '''CREATE TABLE IF NOT EXISTS perfis_clientes (
      id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL, cliente_id TEXT NOT NULL,
      auth_backend_id TEXT, status TEXT NOT NULL DEFAULT 'inativo',
      criado_em TEXT NOT NULL, atualizado_em TEXT NOT NULL,
      UNIQUE(comercio_id, cliente_id),
      FOREIGN KEY (comercio_id) REFERENCES comercios(id) ON DELETE CASCADE
    )''',
    '''CREATE TABLE IF NOT EXISTS carrinhos (
      id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL, cliente_id TEXT,
      status TEXT NOT NULL DEFAULT 'aberto', criado_em TEXT NOT NULL,
      atualizado_em TEXT NOT NULL,
      FOREIGN KEY (comercio_id) REFERENCES comercios(id) ON DELETE CASCADE
    )''',
    '''CREATE TABLE IF NOT EXISTS carrinho_itens (
      id TEXT PRIMARY KEY, carrinho_id TEXT NOT NULL, produto_id TEXT NOT NULL,
      quantidade REAL NOT NULL, preco_unitario REAL NOT NULL,
      FOREIGN KEY (carrinho_id) REFERENCES carrinhos(id) ON DELETE CASCADE,
      FOREIGN KEY (produto_id) REFERENCES estoque(id)
    )''',
    '''CREATE TABLE IF NOT EXISTS consentimentos_privacidade (
      id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL, titular_tipo TEXT NOT NULL,
      titular_id TEXT NOT NULL, finalidade TEXT NOT NULL, concedido INTEGER NOT NULL,
      versao_termo TEXT NOT NULL, registrado_em TEXT NOT NULL,
      FOREIGN KEY (comercio_id) REFERENCES comercios(id) ON DELETE CASCADE
    )''',
    '''CREATE TABLE IF NOT EXISTS solicitacoes_privacidade (
      id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL, titular_tipo TEXT NOT NULL,
      titular_id TEXT NOT NULL, tipo TEXT NOT NULL, status TEXT NOT NULL,
      solicitado_em TEXT NOT NULL, concluido_em TEXT,
      FOREIGN KEY (comercio_id) REFERENCES comercios(id) ON DELETE CASCADE
    )''',
    '''CREATE TABLE IF NOT EXISTS whatsapp_fila (
      id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL, destinatario TEXT NOT NULL,
      template TEXT, payload_json TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'simulado',
      criado_em TEXT NOT NULL, atualizado_em TEXT NOT NULL,
      FOREIGN KEY (comercio_id) REFERENCES comercios(id) ON DELETE CASCADE
    )''',
  ];

  static const _indices = <String>[
    'CREATE INDEX IF NOT EXISTS idx_estoque_destino ON estoque(comercio_id, estoque_destino, ativo)',
    'CREATE INDEX IF NOT EXISTS idx_catalogo_nome ON catalogo_produtos(nome, marca)',
    'CREATE INDEX IF NOT EXISTS idx_sugestoes_status ON catalogo_sugestoes(status, criado_em)',
    'CREATE INDEX IF NOT EXISTS idx_assinatura_eventos ON assinatura_eventos(comercio_id, criado_em)',
    'CREATE INDEX IF NOT EXISTS idx_cardapio_comercio ON cardapio_itens(comercio_id, ativo)',
    'CREATE INDEX IF NOT EXISTS idx_carrinhos_comercio ON carrinhos(comercio_id, status)',
  ];

  static Future<void> _backup(Database db) async {
    final agora = DateTime.now().toUtc().toIso8601String();
    for (final tabela in <String>[
      'comercios',
      'usuarios',
      'configuracoes',
      'estoque',
      'fila_sincronizacao',
      'integracoes_configuracao',
    ]) {
      final dados = await db.query(tabela);
      final estrutura = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
        [tabela],
      );
      await db.insert('backups_logicos', {
        'versao_origem': 5,
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
