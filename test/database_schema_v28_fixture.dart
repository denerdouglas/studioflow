import 'package:sqflite/sqflite.dart';

abstract final class DatabaseSchemaV1Fixture {
  static Future<void> criar(Database db, int version) async {
    await db.execute('''
      CREATE TABLE clientes (
        id TEXT PRIMARY KEY,
        nome TEXT NOT NULL,
        whatsapp TEXT NOT NULL,
        telefone TEXT,
        email TEXT,
        data_nascimento TEXT,
        profissional_principal_id TEXT,
        profissional_secundaria_id TEXT,
        observacoes TEXT,
        ativo INTEGER NOT NULL DEFAULT 1,
        data_cadastro TEXT NOT NULL,
        ultimo_atendimento TEXT,
        total_atendimentos INTEGER NOT NULL DEFAULT 0,
        total_gasto REAL NOT NULL DEFAULT 0,
        pontos_fidelidade INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE anamneses (
        id TEXT PRIMARY KEY,
        cliente_id TEXT NOT NULL,
        tipo_ficha TEXT NOT NULL,

        possui_alergias INTEGER NOT NULL DEFAULT 0,
        descricao_alergias TEXT,

        usa_medicamentos INTEGER NOT NULL DEFAULT 0,
        medicamentos TEXT,

        possui_problemas_pele INTEGER NOT NULL DEFAULT 0,
        problemas_pele TEXT,

        possui_diabetes INTEGER NOT NULL DEFAULT 0,
        possui_pressao_alta INTEGER NOT NULL DEFAULT 0,
        esta_gestante INTEGER NOT NULL DEFAULT 0,
        fez_cirurgia_recente INTEGER NOT NULL DEFAULT 0,
        usa_anticoagulante INTEGER NOT NULL DEFAULT 0,
        possui_sensibilidade INTEGER NOT NULL DEFAULT 0,
        usa_acidos INTEGER NOT NULL DEFAULT 0,

        possui_micose INTEGER NOT NULL DEFAULT 0,
        possui_unha_encravada INTEGER NOT NULL DEFAULT 0,
        roe_unhas INTEGER NOT NULL DEFAULT 0,
        usa_alongamento INTEGER NOT NULL DEFAULT 0,

        possui_sensibilidade_ocular INTEGER NOT NULL DEFAULT 0,
        usa_lentes_contato INTEGER NOT NULL DEFAULT 0,
        fez_cirurgia_ocular INTEGER NOT NULL DEFAULT 0,

        possui_quimica_cabelo INTEGER NOT NULL DEFAULT 0,
        possui_queda_cabelo INTEGER NOT NULL DEFAULT 0,

        formato_preferido TEXT,
        comprimento_preferido TEXT,

        restricoes TEXT,
        observacoes TEXT,

        cliente_confirmou_informacoes INTEGER NOT NULL DEFAULT 0,
        autorizou_procedimento INTEGER NOT NULL DEFAULT 0,
        assinatura_cliente TEXT,

        data_criacao TEXT NOT NULL,
        data_atualizacao TEXT NOT NULL,

        FOREIGN KEY (cliente_id)
          REFERENCES clientes (id)
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_anamneses_cliente
      ON anamneses (cliente_id)
    ''');
    await db.execute('''
      CREATE TABLE profissionais (
        id TEXT PRIMARY KEY,
        nome TEXT NOT NULL,
        whatsapp TEXT NOT NULL,
        email TEXT,
        cargo TEXT NOT NULL,
        foto_perfil TEXT,
        ativo INTEGER NOT NULL DEFAULT 1,
        percentual_comissao REAL NOT NULL DEFAULT 50,
        meta_mensal REAL NOT NULL DEFAULT 0,
        faturamento_mes REAL NOT NULL DEFAULT 0,
        data_cadastro TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE servicos (
        id TEXT PRIMARY KEY,
        nome TEXT NOT NULL,
        categoria TEXT NOT NULL,
        descricao TEXT,
        preco REAL NOT NULL,
        duracao_minutos INTEGER NOT NULL,
        ativo INTEGER NOT NULL DEFAULT 1,
        comissao_percentual REAL,
        custo_estimado REAL NOT NULL DEFAULT 0,
        data_cadastro TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE profissional_servicos (
        profissional_id TEXT NOT NULL,
        servico_id TEXT NOT NULL,

        PRIMARY KEY (
          profissional_id,
          servico_id
        ),

        FOREIGN KEY (profissional_id)
          REFERENCES profissionais (id)
          ON DELETE CASCADE,

        FOREIGN KEY (servico_id)
          REFERENCES servicos (id)
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE agendamentos (
        id TEXT PRIMARY KEY,
        cliente_id TEXT NOT NULL,
        profissional_id TEXT NOT NULL,
        servico_id TEXT NOT NULL,

        inicio TEXT NOT NULL,
        fim TEXT NOT NULL,

        status TEXT NOT NULL DEFAULT 'agendado',
        forma_pagamento TEXT,

        valor_servico REAL NOT NULL,
        desconto REAL NOT NULL DEFAULT 0,
        valor_recebido REAL NOT NULL DEFAULT 0,

        confirmado INTEGER NOT NULL DEFAULT 0,
        compareceu INTEGER NOT NULL DEFAULT 0,

        observacoes TEXT,
        data_criacao TEXT NOT NULL,

        FOREIGN KEY (cliente_id)
          REFERENCES clientes (id),

        FOREIGN KEY (profissional_id)
          REFERENCES profissionais (id),

        FOREIGN KEY (servico_id)
          REFERENCES servicos (id)
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_agendamentos_inicio
      ON agendamentos (inicio)
    ''');

    await db.execute('''
      CREATE INDEX idx_agendamentos_cliente
      ON agendamentos (cliente_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_agendamentos_profissional
      ON agendamentos (profissional_id)
    ''');
    await db.execute('''
      CREATE TABLE estoque (
        id TEXT PRIMARY KEY,
        nome TEXT NOT NULL,
        categoria TEXT NOT NULL,
        tipo TEXT NOT NULL,

        quantidade_atual REAL NOT NULL DEFAULT 0,
        estoque_minimo REAL NOT NULL DEFAULT 0,
        unidade TEXT NOT NULL,
        conteudo_por_unidade REAL NOT NULL DEFAULT 1,
        unidade_conteudo TEXT NOT NULL DEFAULT '',
        revisao_modelagem_estoque INTEGER NOT NULL DEFAULT 0,

        custo_unitario REAL NOT NULL DEFAULT 0,
        fornecedor TEXT,
        codigo_barras TEXT,
        data_validade TEXT,

        ativo INTEGER NOT NULL DEFAULT 1,
        descontar_automaticamente INTEGER NOT NULL DEFAULT 1,

        observacoes TEXT,
        data_cadastro TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE movimentacoes_estoque (
        id TEXT PRIMARY KEY,
        item_estoque_id TEXT NOT NULL,
        tipo TEXT NOT NULL,

        quantidade REAL NOT NULL,
        quantidade_anterior REAL NOT NULL,
        quantidade_posterior REAL NOT NULL,

        data TEXT NOT NULL,
        motivo TEXT,

        agendamento_id TEXT,
        profissional_id TEXT,
        usuario_responsavel_id TEXT,

        FOREIGN KEY (item_estoque_id)
          REFERENCES estoque (id)
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE manutencoes (
        id TEXT PRIMARY KEY,
        item_estoque_id TEXT NOT NULL,
        nome_item TEXT NOT NULL,

        tipo TEXT NOT NULL,
        status TEXT NOT NULL,

        data_programada TEXT NOT NULL,
        data_conclusao TEXT,

        dias_aviso_antecipado INTEGER NOT NULL DEFAULT 2,

        custo REAL,
        prestador TEXT,
        observacoes TEXT,

        FOREIGN KEY (item_estoque_id)
          REFERENCES estoque (id)
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE movimentacoes_financeiras (
        id TEXT PRIMARY KEY,
        tipo TEXT NOT NULL,
        descricao TEXT NOT NULL,
        valor REAL NOT NULL,

        forma_pagamento TEXT,
        status TEXT NOT NULL DEFAULT 'pago',

        data TEXT NOT NULL,
        data_criacao TEXT NOT NULL,

        categoria TEXT,
        cliente_id TEXT,
        profissional_id TEXT,
        agendamento_id TEXT,
        servico_id TEXT,
        usuario_responsavel_id TEXT,

        observacoes TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE comissoes (
        id TEXT PRIMARY KEY,
        profissional_id TEXT NOT NULL,
        agendamento_id TEXT NOT NULL,
        servico_id TEXT NOT NULL,

        valor_servico REAL NOT NULL,
        percentual_comissao REAL NOT NULL,
        valor_comissao REAL NOT NULL,

        data_geracao TEXT NOT NULL,
        data_pagamento TEXT,

        status TEXT NOT NULL DEFAULT 'pendente',
        observacoes TEXT,

        FOREIGN KEY (profissional_id)
          REFERENCES profissionais (id),

        FOREIGN KEY (agendamento_id)
          REFERENCES agendamentos (id),

        FOREIGN KEY (servico_id)
          REFERENCES servicos (id)
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_financeiro_data
      ON movimentacoes_financeiras (data)
    ''');

    await db.execute('''
      CREATE INDEX idx_comissoes_profissional
      ON comissoes (profissional_id)
    ''');
    await db.execute('''
      CREATE TABLE configuracoes (
        chave TEXT PRIMARY KEY,
        valor TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE notificacoes (
        id TEXT PRIMARY KEY,
        tipo TEXT NOT NULL,
        titulo TEXT NOT NULL,
        mensagem TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pendente',
        data_criacao TEXT NOT NULL,
        data_agendada TEXT,
        data_envio TEXT,
        referencia_id TEXT
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_notificacoes_status
      ON notificacoes (status)
    ''');
  }
}
