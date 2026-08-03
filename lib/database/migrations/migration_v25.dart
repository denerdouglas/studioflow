import 'package:sqflite/sqflite.dart';

abstract final class MigrationV25 {
  static Future<void> executar(Database db) async {
    for (final column in const {
      'booking_slug': 'TEXT',
      'booking_enabled': 'INTEGER NOT NULL DEFAULT 1',
      'booking_public_url': 'TEXT',
      'booking_created_at': 'TEXT',
      'booking_updated_at': 'TEXT',
      'booking_settings': "TEXT NOT NULL DEFAULT '{}'",
      'loja_habilitada': 'INTEGER NOT NULL DEFAULT 0',
      'loja_configuracao': "TEXT NOT NULL DEFAULT '{}'",
    }.entries) {
      await _addColumn(db, 'comercios', column.key, column.value);
    }
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_comercios_booking_slug ON comercios(booking_slug) WHERE booking_slug IS NOT NULL',
    );
    final businesses = await db.query(
      'comercios',
      columns: ['id', 'nome', 'booking_slug'],
    );
    final used = <String>{};
    for (final business in businesses) {
      final current = business['booking_slug'] as String?;
      if (current != null && current.isNotEmpty) {
        used.add(current);
        continue;
      }
      var base = _slug(business['nome'] as String? ?? 'studio');
      if (base.length < 3 || _reserved.contains(base)) base = 'studio-$base';
      var candidate = base;
      var suffix = 2;
      while (used.contains(candidate)) {
        candidate = '$base-${suffix++}';
      }
      used.add(candidate);
      final now = DateTime.now().toUtc().toIso8601String();
      await db.update(
        'comercios',
        {
          'booking_slug': candidate,
          'booking_enabled': 1,
          'booking_public_url':
              'https://studioflowapp.com.br/agendar/$candidate',
          'booking_created_at': now,
          'booking_updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [business['id']],
      );
    }
    await db.execute('''CREATE TABLE IF NOT EXISTS booking_slug_aliases (
      slug TEXT PRIMARY KEY, comercio_id TEXT NOT NULL, criado_em TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS ia_conversas (
      id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL, usuario_id TEXT NOT NULL,
      unidade_id TEXT, contexto TEXT NOT NULL DEFAULT '{}', criado_em TEXT NOT NULL,
      atualizado_em TEXT NOT NULL, UNIQUE(comercio_id, usuario_id)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS ia_mensagens (
      id TEXT PRIMARY KEY, conversa_id TEXT NOT NULL, comercio_id TEXT NOT NULL,
      usuario_id TEXT NOT NULL, papel TEXT NOT NULL, conteudo TEXT NOT NULL,
      intencao TEXT, metadados TEXT, criado_em TEXT NOT NULL,
      FOREIGN KEY(conversa_id) REFERENCES ia_conversas(id) ON DELETE CASCADE
    )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ia_mensagens_conversa ON ia_mensagens(conversa_id, criado_em)',
    );
    await db.execute('''CREATE TABLE IF NOT EXISTS ia_auditoria (
      id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL, usuario_id TEXT NOT NULL,
      unidade_id TEXT, intencao TEXT NOT NULL, acao TEXT NOT NULL,
      confirmado INTEGER NOT NULL DEFAULT 0, resultado TEXT, erro TEXT,
      criado_em TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS comandas_loja (
      id TEXT PRIMARY KEY, numero TEXT NOT NULL, comercio_id TEXT NOT NULL,
      unidade_id TEXT, cliente_id TEXT NOT NULL, profissional_id TEXT,
      status TEXT NOT NULL DEFAULT 'aberta', subtotal REAL NOT NULL DEFAULT 0,
      desconto REAL NOT NULL DEFAULT 0, total REAL NOT NULL DEFAULT 0,
      valor_pago REAL NOT NULL DEFAULT 0, vencimento TEXT, observacoes TEXT,
      venda_id TEXT, finalizada_em TEXT, cancelada_em TEXT, motivo_cancelamento TEXT,
      criado_em TEXT NOT NULL, atualizado_em TEXT NOT NULL,
      UNIQUE(comercio_id, numero)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS comanda_loja_itens (
      id TEXT PRIMARY KEY, comanda_id TEXT NOT NULL, comercio_id TEXT NOT NULL,
      produto_id TEXT NOT NULL, lote_id TEXT, codigo TEXT, nome TEXT NOT NULL,
      quantidade REAL NOT NULL, valor_unitario REAL NOT NULL,
      desconto REAL NOT NULL DEFAULT 0, subtotal REAL NOT NULL,
      profissional_id TEXT, comissao_percentual REAL,
      FOREIGN KEY(comanda_id) REFERENCES comandas_loja(id) ON DELETE RESTRICT
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS comanda_loja_pagamentos (
      id TEXT PRIMARY KEY, comanda_id TEXT NOT NULL, comercio_id TEXT NOT NULL,
      forma TEXT NOT NULL, valor REAL NOT NULL, status TEXT NOT NULL,
      registrado_em TEXT NOT NULL,
      FOREIGN KEY(comanda_id) REFERENCES comandas_loja(id) ON DELETE RESTRICT
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS contas_receber_loja (
      id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL, unidade_id TEXT,
      cliente_id TEXT NOT NULL, comanda_id TEXT NOT NULL, lote_id TEXT,
      produto_id TEXT, profissional_id TEXT, vencimento TEXT NOT NULL,
      valor_total REAL NOT NULL, valor_recebido REAL NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'pendente', criado_em TEXT NOT NULL,
      atualizado_em TEXT NOT NULL, UNIQUE(comercio_id, comanda_id)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS contas_receber_pagamentos (
      id TEXT PRIMARY KEY, conta_id TEXT NOT NULL, comercio_id TEXT NOT NULL,
      valor REAL NOT NULL, forma TEXT NOT NULL, observacoes TEXT,
      estornado INTEGER NOT NULL DEFAULT 0, registrado_em TEXT NOT NULL,
      estornado_em TEXT,
      FOREIGN KEY(conta_id) REFERENCES contas_receber_loja(id) ON DELETE RESTRICT
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS consignacao_eventos (
      id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL, consignacao_id TEXT NOT NULL,
      peca_id TEXT, produto_id TEXT, tipo TEXT NOT NULL, quantidade REAL NOT NULL DEFAULT 1,
      valor REAL, cliente_id TEXT, profissional_id TEXT, observacoes TEXT,
      criado_em TEXT NOT NULL,
      FOREIGN KEY(consignacao_id) REFERENCES consignacoes(id) ON DELETE RESTRICT
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS comanda_comissoes (
      id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL, comanda_id TEXT NOT NULL,
      item_id TEXT NOT NULL, profissional_id TEXT NOT NULL, percentual REAL NOT NULL,
      valor REAL NOT NULL, status TEXT NOT NULL DEFAULT 'pendente', criado_em TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS comanda_auditoria (
      id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL, comanda_id TEXT NOT NULL,
      usuario_id TEXT NOT NULL, acao TEXT NOT NULL, detalhes TEXT, criado_em TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS cobranca_configuracoes (
      id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL, unidade_id TEXT,
      tipo TEXT NOT NULL, dias INTEGER, dia_fixo INTEGER, ciclo_inicio_dia INTEGER,
      ciclo_fim_dia INTEGER, vencimento_dia INTEGER, ativo INTEGER NOT NULL DEFAULT 1,
      UNIQUE(comercio_id, unidade_id)
    )''');
    await _addColumn(db, 'contas_receber_loja', 'forma_pagamento', 'TEXT');
    await _addColumn(db, 'contas_receber_loja', 'observacoes', 'TEXT');
    for (final column in const {
      'unidade_id': 'TEXT',
      'codigo_referencia': 'TEXT',
      'nome_lote': 'TEXT',
      'data_prevista_recolhimento': 'TEXT',
      'data_encerramento': 'TEXT',
      'prazo_cobranca_dias': 'INTEGER',
      'data_vencimento_padrao': 'TEXT',
      'valor_total_recebido': 'REAL NOT NULL DEFAULT 0',
      'valor_vendido': 'REAL NOT NULL DEFAULT 0',
      'valor_devolvido': 'REAL NOT NULL DEFAULT 0',
      'valor_perdido': 'REAL NOT NULL DEFAULT 0',
      'valor_pagar_fornecedor': 'REAL NOT NULL DEFAULT 0',
      'quantidade_recebida': 'REAL NOT NULL DEFAULT 0',
      'quantidade_vendida': 'REAL NOT NULL DEFAULT 0',
      'quantidade_devolvida': 'REAL NOT NULL DEFAULT 0',
      'quantidade_disponivel': 'REAL NOT NULL DEFAULT 0',
    }.entries) {
      await _addColumn(db, 'consignacoes', column.key, column.value);
    }
    await _addColumn(
      db,
      'agendamentos',
      'origem',
      "TEXT NOT NULL DEFAULT 'interno'",
    );
    await _addColumn(db, 'agendamentos', 'public_token', 'TEXT');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_agendamentos_public_token ON agendamentos(public_token) WHERE public_token IS NOT NULL',
    );
  }

  static const _reserved = {
    'api',
    'admin',
    'privacy',
    'politica-de-privacidade',
    'excluir-conta',
    'termos-de-uso',
    'contato',
    'login',
    'suporte',
    'agendar',
    'assets',
  };

  static String _slug(String value) {
    var result = value.trim().toLowerCase();
    const accents =
        '\u00e1\u00e0\u00e2\u00e3\u00e4\u00e9\u00e8\u00ea\u00eb\u00ed\u00ec\u00ee\u00ef\u00f3\u00f2\u00f4\u00f5\u00f6\u00fa\u00f9\u00fb\u00fc\u00e7\u00f1';
    const plain = 'aaaaaeeeeiiiiooooouuuucn';
    for (var i = 0; i < accents.length; i++) {
      result = result.replaceAll(accents[i], plain[i]);
    }
    result = result
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return result.length > 60
        ? result.substring(0, 60).replaceFirst(RegExp(r'-+$'), '')
        : result;
  }

  static Future<void> _addColumn(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (!columns.any((item) => item['name'] == column)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }
}
