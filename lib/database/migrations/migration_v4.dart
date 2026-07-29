import 'dart:convert';

import 'package:sqflite/sqflite.dart';

abstract final class MigrationV4 {
  static Future<void> executar(Database db, {required bool criarBackup}) async {
    if (criarBackup) await _backup(db);

    const agendamento = <String, String>{
      'pagamento_status': "TEXT NOT NULL DEFAULT 'pendente'",
      'sinal_valor': 'REAL NOT NULL DEFAULT 0',
      'sinal_status': "TEXT NOT NULL DEFAULT 'nao_configurado'",
      'cancelamento_motivo': 'TEXT',
      'reagendado_de_id': 'TEXT',
      'encaixe': 'INTEGER NOT NULL DEFAULT 0',
      'atualizado_em': 'TEXT',
    };
    for (final item in agendamento.entries) {
      await _adicionarColuna(db, 'agendamentos', item.key, item.value);
    }
    const cliente = <String, String>{
      'consentimento_whatsapp': 'INTEGER NOT NULL DEFAULT 0',
      'consentimento_marketing': 'INTEGER NOT NULL DEFAULT 0',
      'profissional_preferido_id': 'TEXT',
      'atualizado_em': 'TEXT',
    };
    for (final item in cliente.entries) {
      await _adicionarColuna(db, 'clientes', item.key, item.value);
    }

    await db.execute('''CREATE TABLE IF NOT EXISTS horarios_profissionais (
      id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL,
      profissional_id TEXT NOT NULL, dia_semana INTEGER NOT NULL,
      inicio TEXT NOT NULL, fim TEXT NOT NULL, intervalo_inicio TEXT,
      intervalo_fim TEXT, ativo INTEGER NOT NULL DEFAULT 1,
      criado_em TEXT NOT NULL, atualizado_em TEXT NOT NULL,
      UNIQUE(comercio_id, profissional_id, dia_semana)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS bloqueios_agenda (
      id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL, profissional_id TEXT,
      inicio TEXT NOT NULL, fim TEXT NOT NULL, tipo TEXT NOT NULL,
      motivo TEXT, criado_por_id TEXT NOT NULL, criado_em TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS agendamento_historico (
      id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL,
      agendamento_id TEXT NOT NULL, usuario_id TEXT NOT NULL,
      acao TEXT NOT NULL, status_anterior TEXT, status_novo TEXT,
      detalhes TEXT, data TEXT NOT NULL,
      FOREIGN KEY (agendamento_id) REFERENCES agendamentos(id) ON DELETE CASCADE
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS links_agendamento (
      id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL, token TEXT NOT NULL,
      unidade_id TEXT, servico_id TEXT, profissional_id TEXT,
      politica_cancelamento TEXT, exige_sinal INTEGER NOT NULL DEFAULT 0,
      expira_em TEXT, status TEXT NOT NULL DEFAULT 'rascunho',
      criado_em TEXT NOT NULL, UNIQUE(comercio_id, token)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS configuracoes_ia (
      comercio_id TEXT PRIMARY KEY, nome_ia TEXT NOT NULL DEFAULT 'Sofia',
      mensagem_apresentacao TEXT NOT NULL DEFAULT '',
      estilo_linguagem TEXT NOT NULL DEFAULT 'descontraido',
      horario_inicio TEXT NOT NULL DEFAULT '08:00',
      horario_fim TEXT NOT NULL DEFAULT '18:00',
      politica_cancelamento TEXT NOT NULL DEFAULT '',
      instrucao_transferencia TEXT NOT NULL DEFAULT '',
      transferir_palavras TEXT NOT NULL DEFAULT 'humano,atendente,pessoa',
      ativo INTEGER NOT NULL DEFAULT 1, atualizado_em TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS faq_ia (
      id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL, pergunta TEXT NOT NULL,
      resposta TEXT NOT NULL, ativo INTEGER NOT NULL DEFAULT 1,
      criado_em TEXT NOT NULL, atualizado_em TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS conversas_simuladas (
      id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL, cliente_id TEXT,
      canal TEXT NOT NULL DEFAULT 'simulador', status TEXT NOT NULL,
      iniciada_em TEXT NOT NULL, encerrada_em TEXT
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS mensagens_simuladas (
      id TEXT PRIMARY KEY, conversa_id TEXT NOT NULL, comercio_id TEXT NOT NULL,
      remetente TEXT NOT NULL, conteudo TEXT NOT NULL, criada_em TEXT NOT NULL,
      FOREIGN KEY (conversa_id) REFERENCES conversas_simuladas(id) ON DELETE CASCADE
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS configuracoes_pagamento (
      comercio_id TEXT PRIMARY KEY, chave_pix TEXT NOT NULL DEFAULT '',
      tipo_chave TEXT NOT NULL DEFAULT 'aleatoria',
      nome_recebedor TEXT NOT NULL DEFAULT '',
      cidade_recebedor TEXT NOT NULL DEFAULT '',
      mensagem_cobranca TEXT NOT NULL DEFAULT '',
      tipo_sinal TEXT NOT NULL DEFAULT 'percentual',
      valor_sinal REAL NOT NULL DEFAULT 0, prazo_horas INTEGER NOT NULL DEFAULT 24,
      politica_cancelamento TEXT NOT NULL DEFAULT '', link_pagamento_base TEXT,
      atualizado_em TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS cobrancas (
      id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL, agendamento_id TEXT,
      cliente_id TEXT, valor REAL NOT NULL, descricao TEXT NOT NULL,
      forma TEXT NOT NULL, pix_copia_cola TEXT, link_pagamento TEXT,
      status TEXT NOT NULL DEFAULT 'pendente', origem_confirmacao TEXT,
      confirmado_por_id TEXT, criado_em TEXT NOT NULL, confirmado_em TEXT
    )''');

    for (final sql in <String>[
      'CREATE INDEX IF NOT EXISTS idx_horarios_comercio_profissional ON horarios_profissionais(comercio_id, profissional_id, dia_semana)',
      'CREATE INDEX IF NOT EXISTS idx_bloqueios_comercio_inicio ON bloqueios_agenda(comercio_id, inicio, fim)',
      'CREATE INDEX IF NOT EXISTS idx_agendamento_historico ON agendamento_historico(comercio_id, agendamento_id, data)',
      'CREATE INDEX IF NOT EXISTS idx_faq_ia_comercio ON faq_ia(comercio_id, ativo)',
      'CREATE INDEX IF NOT EXISTS idx_mensagens_conversa ON mensagens_simuladas(comercio_id, conversa_id, criada_em)',
      'CREATE INDEX IF NOT EXISTS idx_cobrancas_comercio_status ON cobrancas(comercio_id, status, criado_em)',
    ]) {
      await db.execute(sql);
    }

    final agora = DateTime.now().toUtc().toIso8601String();
    await db.rawInsert(
      '''INSERT OR IGNORE INTO configuracoes_ia (
      comercio_id, nome_ia, mensagem_apresentacao, atualizado_em
+    ) SELECT id, 'Sofia',
+      'Olá! Você está falando com ' || nome_exibicao || '. Como posso ajudar?', ?
+      FROM comercios'''
          .replaceAll('+', ''),
      [agora],
    );
    await db.rawInsert(
      '''INSERT OR IGNORE INTO configuracoes_pagamento (
      comercio_id, chave_pix, nome_recebedor, atualizado_em
+    ) SELECT c.id,
+      COALESCE((SELECT valor FROM configuracoes x
+        WHERE x.comercio_id = c.id AND x.chave = c.id || '.chave_pix' LIMIT 1), ''),
+      c.nome_exibicao, ? FROM comercios c'''
          .replaceAll('+', ''),
      [agora],
    );
  }

  static Future<void> _backup(Database db) async {
    final agora = DateTime.now().toUtc().toIso8601String();
    for (final tabela in ['clientes', 'agendamentos', 'configuracoes']) {
      final dados = await db.query(tabela);
      final estrutura = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
        [tabela],
      );
      await db.insert('backups_logicos', {
        'versao_origem': 3,
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
