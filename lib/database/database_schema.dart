import 'package:sqflite/sqflite.dart';

abstract final class DatabaseSchema {
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
        data_cadastro TEXT NOT NULL,
        modalidade_origem TEXT,
        business_id TEXT,
        created_at TEXT,
        updated_at TEXT,
        deleted_at TEXT,
        created_by TEXT,
        updated_by TEXT,
        insumos_json TEXT
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
      CREATE TABLE agendamento_grupos (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        cliente_id TEXT NOT NULL,
        comanda_id TEXT,
        status TEXT,
        observacoes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        created_by TEXT,
        updated_by TEXT
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_agendamento_grupos_business
      ON agendamento_grupos(business_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_agendamento_grupos_cliente
      ON agendamento_grupos(cliente_id)
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
        unidade_id TEXT,
        filial_id TEXT,
        sala_id TEXT,
        cadeira_id TEXT,
        mesa_id TEXT,
        cabine_id TEXT,
        equipamento_id TEXT,
        tempo_real INTEGER,
        modalidade_origem TEXT,
        consumo_previsto_json TEXT,
        consumo_realizado_json TEXT,
        estoque_consumido INTEGER DEFAULT 0,
        business_id TEXT,
        encaixe INTEGER DEFAULT 0,
        grupo_agendamento_id TEXT,
        ordem_no_grupo INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        created_by TEXT,
        updated_by TEXT,

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
      CREATE INDEX idx_agendamentos_unidade ON agendamentos (unidade_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_agendamentos_equipamento ON agendamentos (equipamento_id)
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
        data_cadastro TEXT NOT NULL,
        tipo_produto TEXT,
        localizacao TEXT,
        estoque_maximo REAL,
        estoque_ideal REAL,
        ultima_compra TEXT,
        ultimo_fornecedor TEXT,
        rendimento REAL,
        consumo_medio REAL,
        consumo_maximo REAL,
        consumo_manual INTEGER DEFAULT 0,
        consumo_automatico INTEGER DEFAULT 0,
        business_id TEXT,
        comercio_id TEXT,
        estoque_destino TEXT DEFAULT 'salao',
        catalogo_id TEXT,
        codigo_interno TEXT,
        preco_venda REAL DEFAULT 0,
        modalidade TEXT DEFAULT 'proprio',
        lote TEXT,
        unidade_id TEXT,
        quantidade REAL DEFAULT 0,
        created_at TEXT,
        updated_at TEXT,
        deleted_at TEXT,
        created_by TEXT,
        updated_by TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE movimentacoes_estoque (
        id TEXT PRIMARY KEY,
        item_estoque_id TEXT NOT NULL,
        tipo TEXT NOT NULL,
        finalidade TEXT,

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

    await db.execute('''
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        checksum TEXT,
        applied_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS business_configurations (
        business_id TEXT PRIMARY KEY,
        idioma TEXT DEFAULT 'pt_BR',
        idioma_secundario TEXT,
        moeda TEXT DEFAULT 'BRL',
        formato_data TEXT DEFAULT 'dd/MM/yyyy',
        formato_hora TEXT DEFAULT 'HH:mm',
        formato_moeda TEXT DEFAULT 'R\$ #,##0.00',
        timezone TEXT DEFAULT 'America/Sao_Paulo',
        primeiro_dia_semana INTEGER DEFAULT 0,
        duracao_padrao INTEGER DEFAULT 30,
        politica_comissao TEXT,
        pais TEXT,
        estado TEXT,
        cidade TEXT,
        preferencias_json TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        created_by TEXT,
        updated_by TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS segmento_templates (
        slug TEXT PRIMARY KEY,
        nome TEXT NOT NULL,
        grupo TEXT NOT NULL,
        payload_config_json TEXT NOT NULL,
        versao INTEGER NOT NULL DEFAULT 1,
        checksum TEXT,
        status TEXT DEFAULT 'ativo',
        origem TEXT DEFAULT 'sistema',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS negocio_modalidades (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        modalidade_slug TEXT NOT NULL,
        tipo TEXT NOT NULL,
        ordem_exibicao INTEGER DEFAULT 0,
        icone TEXT,
        cor TEXT,
        ativo INTEGER DEFAULT 1,
        origem TEXT DEFAULT 'importado',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        created_by TEXT,
        updated_by TEXT,
        FOREIGN KEY (modalidade_slug) REFERENCES segmento_templates (slug)
      )
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_negocio_mod_uniq 
      ON negocio_modalidades (business_id, modalidade_slug) 
      WHERE deleted_at IS NULL
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_negocio_mod_business ON negocio_modalidades (business_id)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pacotes (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        nome TEXT NOT NULL,
        preco REAL NOT NULL CHECK(preco >= 0),
        validade_dias INTEGER,
        regras_uso TEXT,
        status INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        created_by TEXT,
        updated_by TEXT
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_pacotes_business ON pacotes (business_id)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pacote_itens (
        id TEXT PRIMARY KEY,
        pacote_id TEXT NOT NULL,
        servico_id TEXT NOT NULL,
        quantidade_sessoes INTEGER NOT NULL CHECK(quantidade_sessoes > 0),
        ordem INTEGER DEFAULT 0,
        duracao_prevista INTEGER,
        valor_referencia REAL,
        profissional_obrigatorio_id TEXT,
        ativo INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        created_by TEXT,
        updated_by TEXT,
        FOREIGN KEY (pacote_id) REFERENCES pacotes (id) ON DELETE CASCADE,
        FOREIGN KEY (servico_id) REFERENCES servicos (id)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_pacote_itens_pacote ON pacote_itens (pacote_id)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pacotes_vendidos (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        pacote_id TEXT NOT NULL,
        cliente_id TEXT NOT NULL,
        data_venda TEXT NOT NULL,
        valor_original REAL NOT NULL CHECK(valor_original >= 0),
        desconto REAL DEFAULT 0 CHECK(desconto >= 0),
        valor_final REAL NOT NULL CHECK(valor_final >= 0),
        forma_pagamento TEXT,
        status TEXT DEFAULT 'ativo',
        validade_inicio TEXT,
        validade_fim TEXT CHECK(validade_fim >= validade_inicio OR validade_fim IS NULL),
        quantidade_sessoes INTEGER NOT NULL,
        sessoes_utilizadas INTEGER NOT NULL DEFAULT 0 CHECK(sessoes_utilizadas >= 0),
        sessoes_restantes INTEGER NOT NULL CHECK(sessoes_restantes >= 0),
        observacoes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        created_by TEXT,
        updated_by TEXT,
        FOREIGN KEY (pacote_id) REFERENCES pacotes (id),
        FOREIGN KEY (cliente_id) REFERENCES clientes (id)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_pacotes_vendidos_business ON pacotes_vendidos (business_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_pacotes_vendidos_cliente ON pacotes_vendidos (cliente_id)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sessoes_pacotes (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        pacote_vendido_id TEXT NOT NULL,
        ordem INTEGER DEFAULT 0,
        servico_id_previsto TEXT,
        servico_id_realizado TEXT,
        data_agendada TEXT,
        horario_inicio TEXT,
        horario_fim TEXT CHECK(horario_fim > horario_inicio OR horario_fim IS NULL),
        profissional_id TEXT,
        agendamento_id TEXT UNIQUE,
        unidade_id TEXT,
        sala_id TEXT,
        equipamento_id TEXT,
        status TEXT DEFAULT 'disponivel',
        valor_atribuido REAL DEFAULT 0 CHECK(valor_atribuido >= 0),
        observacoes TEXT,
        estoque_consumido INTEGER DEFAULT 0,
        estoque_consumido_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        created_by TEXT,
        updated_by TEXT,
        FOREIGN KEY (pacote_vendido_id) REFERENCES pacotes_vendidos (id) ON DELETE CASCADE,
        FOREIGN KEY (servico_id_previsto) REFERENCES servicos (id) ON DELETE SET NULL,
        FOREIGN KEY (servico_id_realizado) REFERENCES servicos (id) ON DELETE SET NULL,
        FOREIGN KEY (profissional_id) REFERENCES profissionais (id),
        FOREIGN KEY (agendamento_id) REFERENCES agendamentos (id)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sessoes_pacotes_vendido ON sessoes_pacotes (pacote_vendido_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sessoes_pacotes_data ON sessoes_pacotes (data_agendada)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS estoque_saldos (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        estoque_id TEXT NOT NULL,
        finalidade TEXT NOT NULL,
        local_id TEXT,
        quantidade_atual REAL DEFAULT 0,
        quantidade_reservada REAL DEFAULT 0,
        estoque_minimo REAL,
        estoque_maximo REAL,
        estoque_ideal REAL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        created_by TEXT,
        updated_by TEXT,
        FOREIGN KEY (estoque_id) REFERENCES estoque (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_estoque_saldos_uniq 
      ON estoque_saldos (business_id, estoque_id, finalidade, COALESCE(local_id, '')) 
      WHERE deleted_at IS NULL
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS creditos_comerciais (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        cliente_id TEXT NOT NULL,
        tipo TEXT NOT NULL,
        codigo TEXT,
        valor REAL NOT NULL CHECK(valor >= 0),
        saldo_restante REAL NOT NULL CHECK(saldo_restante >= 0 AND saldo_restante <= valor),
        validade TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        created_by TEXT,
        updated_by TEXT,
        FOREIGN KEY (cliente_id) REFERENCES clientes (id)
      )
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_creditos_codigo 
      ON creditos_comerciais (business_id, codigo) 
      WHERE codigo IS NOT NULL AND deleted_at IS NULL
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS whatsapp_fila (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        comercio_id TEXT,
        cliente_id TEXT,
        destinatario TEXT,
        agendamento_id TEXT,
        status TEXT NOT NULL,
        idempotency_key TEXT,
        provider TEXT,
        provider_message_id TEXT,
        conversation_id TEXT,
        template_id TEXT,
        template TEXT,
        payload TEXT,
        payload_json TEXT,
        attempt INTEGER DEFAULT 0,
        erro TEXT,
        latencia INTEGER,
        scheduled_at TEXT,
        sent_at TEXT,
        delivered_at TEXT,
        read_at TEXT,
        failed_at TEXT,
        last_attempt_at TEXT,
        created_at TEXT NOT NULL,
        criado_em TEXT,
        updated_at TEXT NOT NULL,
        atualizado_em TEXT,
        deleted_at TEXT,
        created_by TEXT,
        updated_by TEXT
      )
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_whatsapp_fila_idemp 
      ON whatsapp_fila (business_id, provider, idempotency_key) 
      WHERE idempotency_key IS NOT NULL AND deleted_at IS NULL
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ativos_imobilizados (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        estoque_id TEXT NOT NULL,
        data_aquisicao TEXT,
        valor_aquisicao REAL DEFAULT 0 CHECK (valor_aquisicao >= 0),
        numero_serie TEXT,
        patrimonio TEXT,
        localizacao TEXT,
        condicao TEXT,
        garantia_ate TEXT,
        observacoes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        created_by TEXT,
        updated_by TEXT,
        FOREIGN KEY (estoque_id) REFERENCES estoque (id) ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_ativos_imob_estoque_uniq 
      ON ativos_imobilizados (business_id, estoque_id) 
      WHERE deleted_at IS NULL
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_ativos_imob_business 
      ON ativos_imobilizados (business_id)
    ''');
  }
}
