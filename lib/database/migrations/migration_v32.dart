import 'package:sqflite/sqflite.dart';

abstract final class MigrationV32 {
  static Future<void> executar(Database db) async {
    // 1. Criar novas tabelas de pacotes caso ainda não existam, com schema atualizado
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
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pacotes_business ON pacotes (business_id)',
    );

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
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pacote_itens_pacote ON pacote_itens (pacote_id)',
    );

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
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pacotes_vendidos_business ON pacotes_vendidos (business_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pacotes_vendidos_cliente ON pacotes_vendidos (cliente_id)',
    );

    // Para sessoes_pacotes, precisamos recriar se ela existe para relaxar a constraint NOT NULL
    // ou apenas criá-la se não existir.
    // Usaremos a técnica de rename e rebuild para garantir o schema mais recente e sem NOT NULL em servico_id_previsto.
    await db.execute('PRAGMA foreign_keys = OFF');

    // Validar se tabela existe
    final res = await db.query(
      'sqlite_master',
      where: 'type = ? AND name = ?',
      whereArgs: ['table', 'sessoes_pacotes'],
    );
    if (res.isNotEmpty) {
      await db.execute(
        'ALTER TABLE sessoes_pacotes RENAME TO sessoes_pacotes_old',
      );
    }

    await db.execute('''
      CREATE TABLE sessoes_pacotes (
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

    if (res.isNotEmpty) {
      await db.execute(
        'INSERT INTO sessoes_pacotes SELECT * FROM sessoes_pacotes_old',
      );
      await db.execute('DROP TABLE sessoes_pacotes_old');
    }

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sessoes_pacotes_vendido ON sessoes_pacotes (pacote_vendido_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sessoes_pacotes_data ON sessoes_pacotes (data_agendada)',
    );
    await db.execute('PRAGMA foreign_keys = ON');

    // 2. Migrar dados das tabelas legadas para as novas, caso existam.
    // Usamos INSERT OR IGNORE para que migrações parciais não quebrem e preservamos o ID original.

    // A) pacotes_servicos -> pacotes
    final existePacotesServicos = await _tabelaExiste(db, 'pacotes_servicos');
    if (existePacotesServicos) {
      await db.execute('''
        INSERT OR IGNORE INTO pacotes (
          id, business_id, nome, preco, validade_dias, regras_uso, status, 
          created_at, updated_at, created_by, updated_by
        )
        SELECT 
          id, comercio_id, nome, preco_pacote, validade_dias, descricao, ativo,
          criado_em, atualizado_em, criado_por_id, criado_por_id
        FROM pacotes_servicos
      ''');
    }

    // B) pacote_servico_itens -> pacote_itens
    final existePacoteServicoItens = await _tabelaExiste(
      db,
      'pacote_servico_itens',
    );
    if (existePacoteServicoItens) {
      // Nota: pacotes legados usavam o ID do pacote de serviço de forma diferente?
      // Sim, pacote_servico_itens tinha pacote_id.
      await db.execute('''
        INSERT OR IGNORE INTO pacote_itens (
          id, pacote_id, servico_id, quantidade_sessoes, ordem, duracao_prevista,
          valor_referencia, ativo, created_at, updated_at
        )
        SELECT
          id, pacote_id, servico_id, 1, COALESCE(ordem_inicial, 0), duracao_minutos,
          preco_unitario_referencia, 1, '1970-01-01T00:00:00.000Z', '1970-01-01T00:00:00.000Z'
        FROM pacote_servico_itens
      ''');
    }

    // C) pacote_vendas -> pacotes_vendidos
    final existePacoteVendas = await _tabelaExiste(db, 'pacote_vendas');
    if (existePacoteVendas) {
      await db.execute('''
        INSERT OR IGNORE INTO pacotes_vendidos (
          id, business_id, pacote_id, cliente_id, data_venda,
          valor_original, desconto, valor_final, forma_pagamento, status,
          validade_inicio, validade_fim, quantidade_sessoes, sessoes_utilizadas, sessoes_restantes,
          created_at, updated_at, created_by, updated_by
        )
        SELECT
          id, comercio_id, pacote_id, cliente_id, data_compra,
          valor_contratado, desconto_autorizado, valor_contratado - desconto_autorizado, forma_pagamento, 
          status,
          data_compra, validade_em, total_sessoes, 0, total_sessoes, -- sessoes serao recalculadas se necessario
          data_compra, atualizado_em, criado_por_id, criado_por_id
        FROM pacote_vendas
      ''');
    }

    // D) pacote_venda_sessoes -> sessoes_pacotes
    final existePacoteVendaSessoes = await _tabelaExiste(
      db,
      'pacote_venda_sessoes',
    );
    if (existePacoteVendaSessoes) {
      await db.execute('''
        INSERT OR IGNORE INTO sessoes_pacotes (
          id, business_id, pacote_vendido_id, ordem,
          servico_id_previsto, servico_id_realizado,
          data_agendada, profissional_id, agendamento_id,
          status, observacoes, created_at, updated_at
        )
        SELECT
          pvs.id, pvs.comercio_id, pvs.pacote_venda_id, pvs.numero,
          CASE WHEN s_prev.id IS NOT NULL THEN pvs.servico_id ELSE NULL END,
          CASE WHEN pvs.status IN ('realizada', 'faltou_consumida') THEN (CASE WHEN s_prev.id IS NOT NULL THEN pvs.servico_id ELSE NULL END) ELSE NULL END,
          pvs.inicio_planejado, pvs.profissional_id, pvs.agendamento_id,
          pvs.status,
          CASE WHEN s_prev.id IS NULL THEN 'Serviço legado removido. ID original: ' || pvs.servico_id ELSE pvs.observacoes END,
          pvs.atualizado_em, pvs.atualizado_em
        FROM pacote_venda_sessoes pvs
        LEFT JOIN servicos s_prev ON s_prev.id = pvs.servico_id
      ''');
    }
  }

  static Future<bool> _tabelaExiste(Database db, String tableName) async {
    final res = await db.query(
      'sqlite_master',
      where: 'type = ? AND name = ?',
      whereArgs: ['table', tableName],
    );
    return res.isNotEmpty;
  }
}
