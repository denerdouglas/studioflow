import re

with open('lib/database/database_schema.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Add schema_migrations table and other tables
new_tables = """
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
        servico_id_previsto TEXT NOT NULL,
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
        FOREIGN KEY (servico_id_previsto) REFERENCES servicos (id),
        FOREIGN KEY (servico_id_realizado) REFERENCES servicos (id),
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
        cliente_id TEXT,
        agendamento_id TEXT,
        status TEXT NOT NULL,
        idempotency_key TEXT,
        provider TEXT,
        provider_message_id TEXT,
        conversation_id TEXT,
        template_id TEXT,
        payload TEXT,
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
        updated_at TEXT NOT NULL,
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
"""

# Insert new tables at the end of the schema creation
if "schema_migrations" not in content:
    content = content.replace("  }\n}", new_tables + "\n  }\n}")

    with open('lib/database/database_schema.dart', 'w', encoding='utf-8') as f:
        f.write(content)
    print("Schema updated successfully.")
else:
    print("Schema already updated.")
