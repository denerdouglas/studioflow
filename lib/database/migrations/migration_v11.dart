import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// Pacotes de serviços e agendamento automático.
///
/// A migração é aditiva, mantém todos os dados anteriores e registra backup
/// lógico antes de alterar a agenda ou estruturas financeiras.
abstract final class MigrationV11 {
  static Future<void> executar(Database db, {required bool criarBackup}) async {
    if (criarBackup) await _backup(db);

    await _addColumn(db, 'agendamentos', 'pacote_venda_sessao_id', 'TEXT');

    for (final sql in _tables) {
      await db.execute(sql);
    }
    for (final sql in _indexes) {
      await db.execute(sql);
    }
    await _criarPermissoes(db);
  }

  static const _tables = <String>[
    '''CREATE TABLE IF NOT EXISTS pacotes_servicos (
      id TEXT PRIMARY KEY,
      comercio_id TEXT NOT NULL,
      nome TEXT NOT NULL,
      descricao TEXT NOT NULL DEFAULT '',
      categoria TEXT NOT NULL,
      tipo_sequencia TEXT NOT NULL DEFAULT 'livre'
        CHECK (tipo_sequencia IN ('livre', 'obrigatoria')),
      total_sessoes INTEGER NOT NULL CHECK (total_sessoes > 0),
      preco_individual_somado REAL NOT NULL CHECK (preco_individual_somado >= 0),
      preco_pacote REAL NOT NULL CHECK (preco_pacote >= 0),
      desconto REAL NOT NULL DEFAULT 0 CHECK (desconto >= 0),
      validade_dias INTEGER NOT NULL CHECK (validade_dias > 0),
      intervalo_recomendado_dias INTEGER NOT NULL DEFAULT 7,
      forma_pagamento_padrao TEXT,
      permite_parcelamento INTEGER NOT NULL DEFAULT 0,
      max_parcelas INTEGER NOT NULL DEFAULT 1,
      exige_sinal INTEGER NOT NULL DEFAULT 0,
      sinal_padrao REAL NOT NULL DEFAULT 0,
      regras_cancelamento TEXT NOT NULL DEFAULT '',
      regra_falta TEXT NOT NULL DEFAULT 'manter'
        CHECK (regra_falta IN ('manter','consumir','parcial','aprovar')),
      percentual_falta REAL NOT NULL DEFAULT 0,
      permite_transferencia INTEGER NOT NULL DEFAULT 0,
      modo_comissao TEXT NOT NULL DEFAULT 'por_sessao'
        CHECK (modo_comissao IN ('venda','por_sessao','dividida')),
      percentual_vendedor REAL NOT NULL DEFAULT 0,
      observacoes TEXT NOT NULL DEFAULT '',
      ativo INTEGER NOT NULL DEFAULT 1,
      criado_por_id TEXT NOT NULL,
      criado_em TEXT NOT NULL,
      atualizado_em TEXT NOT NULL,
      versao_local INTEGER NOT NULL DEFAULT 1,
      FOREIGN KEY (comercio_id) REFERENCES comercios(id) ON DELETE CASCADE
    )''',
    '''CREATE TABLE IF NOT EXISTS pacote_servico_itens (
      id TEXT PRIMARY KEY,
      comercio_id TEXT NOT NULL,
      pacote_id TEXT NOT NULL,
      servico_id TEXT NOT NULL,
      quantidade INTEGER NOT NULL CHECK (quantidade > 0),
      ordem_inicial INTEGER,
      intervalo_minimo_dias INTEGER NOT NULL DEFAULT 0,
      intervalo_maximo_dias INTEGER,
      duracao_minutos INTEGER NOT NULL CHECK (duracao_minutos > 0),
      preco_unitario_referencia REAL NOT NULL CHECK (preco_unitario_referencia >= 0),
      FOREIGN KEY (pacote_id) REFERENCES pacotes_servicos(id) ON DELETE CASCADE,
      FOREIGN KEY (servico_id) REFERENCES servicos(id),
      FOREIGN KEY (comercio_id) REFERENCES comercios(id) ON DELETE CASCADE
    )''',
    '''CREATE TABLE IF NOT EXISTS pacote_item_profissionais (
      comercio_id TEXT NOT NULL,
      pacote_item_id TEXT NOT NULL,
      profissional_id TEXT NOT NULL,
      PRIMARY KEY (pacote_item_id, profissional_id),
      FOREIGN KEY (pacote_item_id) REFERENCES pacote_servico_itens(id) ON DELETE CASCADE,
      FOREIGN KEY (profissional_id) REFERENCES profissionais(id),
      FOREIGN KEY (comercio_id) REFERENCES comercios(id) ON DELETE CASCADE
    )''',
    '''CREATE TABLE IF NOT EXISTS servico_materiais (
      id TEXT PRIMARY KEY,
      comercio_id TEXT NOT NULL,
      servico_id TEXT NOT NULL,
      estoque_id TEXT NOT NULL,
      quantidade REAL NOT NULL CHECK (quantidade > 0),
      ativo INTEGER NOT NULL DEFAULT 1,
      UNIQUE(comercio_id, servico_id, estoque_id),
      FOREIGN KEY (servico_id) REFERENCES servicos(id) ON DELETE CASCADE,
      FOREIGN KEY (estoque_id) REFERENCES estoque(id),
      FOREIGN KEY (comercio_id) REFERENCES comercios(id) ON DELETE CASCADE
    )''',
    '''CREATE TABLE IF NOT EXISTS pacote_vendas (
      id TEXT PRIMARY KEY,
      comercio_id TEXT NOT NULL,
      pacote_id TEXT NOT NULL,
      cliente_id TEXT NOT NULL,
      vendedor_profissional_id TEXT NOT NULL,
      valor_contratado REAL NOT NULL CHECK (valor_contratado >= 0),
      desconto_autorizado REAL NOT NULL DEFAULT 0,
      valor_pago REAL NOT NULL DEFAULT 0,
      valor_pendente REAL NOT NULL DEFAULT 0,
      sinal REAL NOT NULL DEFAULT 0,
      forma_pagamento TEXT NOT NULL,
      quantidade_parcelas INTEGER NOT NULL DEFAULT 1,
      total_sessoes INTEGER NOT NULL,
      data_compra TEXT NOT NULL,
      validade_em TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'ativo'
        CHECK (status IN ('ativo','pausado','concluido','cancelado','vencido')),
      pausado_em TEXT,
      motivo_cancelamento TEXT,
      cliente_origem_id TEXT,
      comanda_referencia TEXT,
      criado_por_id TEXT NOT NULL,
      atualizado_em TEXT NOT NULL,
      versao_local INTEGER NOT NULL DEFAULT 1,
      FOREIGN KEY (pacote_id) REFERENCES pacotes_servicos(id),
      FOREIGN KEY (cliente_id) REFERENCES clientes(id),
      FOREIGN KEY (vendedor_profissional_id) REFERENCES profissionais(id),
      FOREIGN KEY (comercio_id) REFERENCES comercios(id) ON DELETE CASCADE
    )''',
    '''CREATE TABLE IF NOT EXISTS pacote_venda_sessoes (
      id TEXT PRIMARY KEY,
      comercio_id TEXT NOT NULL,
      pacote_venda_id TEXT NOT NULL,
      pacote_item_id TEXT NOT NULL,
      servico_id TEXT NOT NULL,
      numero INTEGER NOT NULL,
      ordem INTEGER,
      duracao_minutos INTEGER NOT NULL,
      intervalo_minimo_dias INTEGER NOT NULL DEFAULT 0,
      intervalo_maximo_dias INTEGER,
      profissional_id TEXT,
      agendamento_id TEXT,
      inicio_planejado TEXT,
      status TEXT NOT NULL DEFAULT 'disponivel'
        CHECK (status IN (
          'disponivel','agendada','realizada','cancelada',
          'faltou_consumida','vencida'
        )),
      credito_consumido REAL NOT NULL DEFAULT 0
        CHECK (credito_consumido >= 0 AND credito_consumido <= 1),
      realizada_em TEXT,
      cancelada_em TEXT,
      falta_regra_aplicada TEXT,
      observacoes TEXT,
      atualizado_em TEXT NOT NULL,
      UNIQUE(comercio_id, pacote_venda_id, numero),
      FOREIGN KEY (pacote_venda_id) REFERENCES pacote_vendas(id) ON DELETE CASCADE,
      FOREIGN KEY (pacote_item_id) REFERENCES pacote_servico_itens(id),
      FOREIGN KEY (servico_id) REFERENCES servicos(id),
      FOREIGN KEY (profissional_id) REFERENCES profissionais(id),
      FOREIGN KEY (agendamento_id) REFERENCES agendamentos(id),
      FOREIGN KEY (comercio_id) REFERENCES comercios(id) ON DELETE CASCADE
    )''',
    '''CREATE TABLE IF NOT EXISTS pacote_parcelas (
      id TEXT PRIMARY KEY,
      comercio_id TEXT NOT NULL,
      pacote_venda_id TEXT NOT NULL,
      numero INTEGER NOT NULL,
      valor REAL NOT NULL CHECK (valor >= 0),
      vencimento TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pendente'
        CHECK (status IN ('pendente','paga','vencida','cancelada')),
      paga_em TEXT,
      UNIQUE(comercio_id, pacote_venda_id, numero),
      FOREIGN KEY (pacote_venda_id) REFERENCES pacote_vendas(id) ON DELETE CASCADE
    )''',
    '''CREATE TABLE IF NOT EXISTS pacote_pagamentos (
      id TEXT PRIMARY KEY,
      comercio_id TEXT NOT NULL,
      pacote_venda_id TEXT NOT NULL,
      parcela_id TEXT,
      valor REAL NOT NULL CHECK (valor > 0),
      forma_pagamento TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'confirmado',
      movimento_financeiro_id TEXT UNIQUE,
      recebido_por_id TEXT NOT NULL,
      recebido_em TEXT NOT NULL,
      estornado_em TEXT,
      FOREIGN KEY (pacote_venda_id) REFERENCES pacote_vendas(id) ON DELETE CASCADE,
      FOREIGN KEY (parcela_id) REFERENCES pacote_parcelas(id)
    )''',
    '''CREATE TABLE IF NOT EXISTS pacote_comissoes (
      id TEXT PRIMARY KEY,
      comercio_id TEXT NOT NULL,
      pacote_venda_id TEXT NOT NULL,
      sessao_id TEXT,
      profissional_id TEXT NOT NULL,
      papel TEXT NOT NULL CHECK (papel IN ('vendedor','executor')),
      valor_base REAL NOT NULL,
      percentual REAL NOT NULL,
      valor_comissao REAL NOT NULL,
      status TEXT NOT NULL DEFAULT 'pendente',
      criada_em TEXT NOT NULL,
      UNIQUE(comercio_id, pacote_venda_id, sessao_id, profissional_id, papel)
    )''',
    '''CREATE TABLE IF NOT EXISTS pacote_auditoria (
      id TEXT PRIMARY KEY,
      comercio_id TEXT NOT NULL,
      pacote_venda_id TEXT,
      pacote_id TEXT,
      sessao_id TEXT,
      usuario_id TEXT NOT NULL,
      acao TEXT NOT NULL,
      dados_json TEXT NOT NULL DEFAULT '{}',
      criado_em TEXT NOT NULL
    )''',
    '''CREATE TABLE IF NOT EXISTS pacote_alertas (
      id TEXT PRIMARY KEY,
      comercio_id TEXT NOT NULL,
      pacote_venda_id TEXT NOT NULL,
      tipo TEXT NOT NULL,
      mensagem TEXT NOT NULL,
      canal TEXT NOT NULL DEFAULT 'app',
      status TEXT NOT NULL DEFAULT 'pendente',
      referencia_data TEXT,
      criado_em TEXT NOT NULL,
      UNIQUE(comercio_id, pacote_venda_id, tipo, referencia_data)
    )''',
  ];

  static const _indexes = <String>[
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_agendamento_pacote_sessao '
        'ON agendamentos(pacote_venda_sessao_id) '
        'WHERE pacote_venda_sessao_id IS NOT NULL',
    'CREATE INDEX IF NOT EXISTS idx_pacotes_comercio '
        'ON pacotes_servicos(comercio_id, ativo, nome)',
    'CREATE INDEX IF NOT EXISTS idx_pacote_vendas_cliente '
        'ON pacote_vendas(comercio_id, cliente_id, status, validade_em)',
    'CREATE INDEX IF NOT EXISTS idx_pacote_sessoes_venda '
        'ON pacote_venda_sessoes(comercio_id, pacote_venda_id, numero)',
    'CREATE INDEX IF NOT EXISTS idx_pacote_sessoes_agendamento '
        'ON pacote_venda_sessoes(comercio_id, agendamento_id)',
    'CREATE INDEX IF NOT EXISTS idx_pacote_parcelas_status '
        'ON pacote_parcelas(comercio_id, status, vencimento)',
    'CREATE INDEX IF NOT EXISTS idx_pacote_alertas '
        'ON pacote_alertas(comercio_id, status, referencia_data)',
  ];

  static Future<void> _criarPermissoes(Database db) async {
    const acoes = <String>[
      'visualizarPacotes',
      'criarPacotes',
      'editarPacotes',
      'venderPacotes',
      'aplicarDescontoPacote',
      'alterarValidadePacote',
      'cancelarPacote',
      'baixarSessaoPacote',
      'estornarPagamentoPacote',
      'transferirPacote',
      'consultarRelatoriosPacotes',
    ];
    final agora = DateTime.now().toUtc().toIso8601String();
    final usuarios = await db.query(
      'usuarios',
      columns: ['id', 'comercio_id', 'funcao'],
    );
    for (final usuario in usuarios) {
      for (final acao in acoes) {
        await db.insert('permissoes_acoes', {
          'usuario_id': usuario['id'],
          'comercio_id': usuario['comercio_id'],
          'acao': acao,
          'permitido': usuario['funcao'] == 'dono' ? 1 : 0,
          'atualizado_em': agora,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
  }

  static Future<void> _backup(Database db) async {
    final now = DateTime.now().toUtc().toIso8601String();
    for (final table in <String>[
      'servicos',
      'agendamentos',
      'movimentacoes_financeiras',
      'comissoes',
      'estoque',
      'movimentacoes_estoque',
      'fila_sincronizacao',
    ]) {
      final data = await db.query(table);
      final structure = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
        [table],
      );
      await db.insert('backups_logicos', {
        'versao_origem': 10,
        'tabela': table,
        'estrutura_sql': structure.isEmpty ? null : structure.first['sql'],
        'dados_json': jsonEncode(data),
        'criado_em': now,
      });
    }
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
