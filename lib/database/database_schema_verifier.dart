import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';
import 'migrations/migration_v40.dart';
import 'migrations/migration_v41.dart';

abstract final class DatabaseSchemaVerifier {
  /// Executa verificações e reparos idempotentes no schema.
  /// Chamado sempre ao abrir o banco, garantindo que o app nunca quebre
  /// por furos de migrations passadas.
  static Future<void> repair(Database db) async {
    try {
      // Usamos transação para que, se algo falhar no meio, as modificações
      // dessa etapa específica sejam revertidas e não deixem o banco quebrado.
      await db.transaction((txn) async {
        await _verificarEAdicionarColunas(txn);
        await _garantirTabelasAdicionais(txn);
        await _backfills(txn);
      });
      debugPrint('SchemaRepair: Executado com sucesso.');
    } catch (e, stack) {
      debugPrint('SchemaRepair Erro Crítico: $e\n$stack');
    }
  }

  static Future<void> _verificarEAdicionarColunas(Transaction txn) async {
    final colunasFinanceiro = await _getColunas(
      txn,
      'movimentacoes_financeiras',
    );
    if (colunasFinanceiro.isNotEmpty) {
      await _addCol(
        txn,
        'movimentacoes_financeiras',
        colunasFinanceiro,
        'centro_resultado',
        'TEXT',
      );
      await _addCol(
        txn,
        'movimentacoes_financeiras',
        colunasFinanceiro,
        'entidade_origem',
        'TEXT',
      );
      await _addCol(
        txn,
        'movimentacoes_financeiras',
        colunasFinanceiro,
        'entidade_origem_id',
        'TEXT',
      );
    }

    // ESTOQUE
    final colunasEstoque = await _getColunas(txn, 'estoque');
    if (colunasEstoque.isNotEmpty) {
      await _addCol(txn, 'estoque', colunasEstoque, 'business_id', 'TEXT');
      await _addCol(txn, 'estoque', colunasEstoque, 'comercio_id', 'TEXT');
      await _addCol(
        txn,
        'estoque',
        colunasEstoque,
        'estoque_destino',
        "TEXT DEFAULT 'salao'",
      );
      await _addCol(txn, 'estoque', colunasEstoque, 'catalogo_id', 'TEXT');
      await _addCol(txn, 'estoque', colunasEstoque, 'codigo_interno', 'TEXT');
      await _addCol(
        txn,
        'estoque',
        colunasEstoque,
        'preco_venda',
        'REAL DEFAULT 0',
      );
      await _addCol(
        txn,
        'estoque',
        colunasEstoque,
        'modalidade',
        "TEXT DEFAULT 'proprio'",
      );
      await _addCol(txn, 'estoque', colunasEstoque, 'lote', 'TEXT');
      await _addCol(txn, 'estoque', colunasEstoque, 'unidade_id', 'TEXT');
      await _addCol(
        txn,
        'estoque',
        colunasEstoque,
        'quantidade',
        'REAL DEFAULT 0',
      );
      await _addCol(txn, 'estoque', colunasEstoque, 'created_at', 'TEXT');
      await _addCol(txn, 'estoque', colunasEstoque, 'updated_at', 'TEXT');
      await _addCol(txn, 'estoque', colunasEstoque, 'deleted_at', 'TEXT');
      await _addCol(txn, 'estoque', colunasEstoque, 'created_by', 'TEXT');
      await _addCol(txn, 'estoque', colunasEstoque, 'updated_by', 'TEXT');
    }

    // MOVIMENTACOES_ESTOQUE
    final colunasMovEstoque = await _getColunas(txn, 'movimentacoes_estoque');
    if (colunasMovEstoque.isNotEmpty) {
      await _addCol(
        txn,
        'movimentacoes_estoque',
        colunasMovEstoque,
        'finalidade',
        'TEXT',
      );
      await _addCol(
        txn,
        'movimentacoes_estoque',
        colunasMovEstoque,
        'origem',
        'TEXT',
      );
      await _addCol(
        txn,
        'movimentacoes_estoque',
        colunasMovEstoque,
        'referencia_id',
        'TEXT',
      );
      await _addCol(
        txn,
        'movimentacoes_estoque',
        colunasMovEstoque,
        'justificativa_negativo',
        'TEXT',
      );
      await _addCol(
        txn,
        'movimentacoes_estoque',
        colunasMovEstoque,
        'business_id',
        'TEXT',
      );
      await _addCol(
        txn,
        'movimentacoes_estoque',
        colunasMovEstoque,
        'comercio_id',
        'TEXT',
      );
      await _addCol(
        txn,
        'movimentacoes_estoque',
        colunasMovEstoque,
        'idempotency_key',
        'TEXT',
      );
    }

    // AGENDAMENTOS
    final colunasAgendamentos = await _getColunas(txn, 'agendamentos');
    if (colunasAgendamentos.isNotEmpty) {
      await _addCol(
        txn,
        'agendamentos',
        colunasAgendamentos,
        'business_id',
        'TEXT',
      );
      await _addCol(
        txn,
        'agendamentos',
        colunasAgendamentos,
        'comercio_id',
        'TEXT',
      );
      await _addCol(
        txn,
        'agendamentos',
        colunasAgendamentos,
        'grupo_agendamento_id',
        'TEXT',
      );
      await _addCol(
        txn,
        'agendamentos',
        colunasAgendamentos,
        'ordem_no_grupo',
        'INTEGER',
      );
      await _addCol(
        txn,
        'agendamentos',
        colunasAgendamentos,
        'consumo_previsto_json',
        'TEXT',
      );
      await _addCol(
        txn,
        'agendamentos',
        colunasAgendamentos,
        'consumo_realizado_json',
        'TEXT',
      );
      await _addCol(
        txn,
        'agendamentos',
        colunasAgendamentos,
        'estoque_consumido',
        'INTEGER DEFAULT 0',
      );
      await _addCol(
        txn,
        'agendamentos',
        colunasAgendamentos,
        'encaixe',
        'INTEGER DEFAULT 0',
      );
      await _addCol(
        txn,
        'agendamentos',
        colunasAgendamentos,
        'created_at',
        'TEXT',
      );
      await _addCol(
        txn,
        'agendamentos',
        colunasAgendamentos,
        'updated_at',
        'TEXT',
      );
      await _addCol(
        txn,
        'agendamentos',
        colunasAgendamentos,
        'deleted_at',
        'TEXT',
      );
      await _addCol(
        txn,
        'agendamentos',
        colunasAgendamentos,
        'created_by',
        'TEXT',
      );
      await _addCol(
        txn,
        'agendamentos',
        colunasAgendamentos,
        'updated_by',
        'TEXT',
      );
    }

    // SERVICOS
    final colunasServicos = await _getColunas(txn, 'servicos');
    if (colunasServicos.isNotEmpty) {
      await _addCol(txn, 'servicos', colunasServicos, 'insumos_json', 'TEXT');
    }
  }

  static Future<void> _garantirTabelasAdicionais(Transaction txn) async {
    await MigrationV40.executar(txn);
    await MigrationV41.executar(txn);
    // Pacotes (v32)
    await txn.execute('''
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
    await txn.execute(
      'CREATE INDEX IF NOT EXISTS idx_pacotes_business ON pacotes (business_id)',
    );

    await txn.execute('''
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
    await txn.execute(
      'CREATE INDEX IF NOT EXISTS idx_pacote_itens_pacote ON pacote_itens (pacote_id)',
    );

    await txn.execute('''
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
    await txn.execute(
      'CREATE INDEX IF NOT EXISTS idx_pacotes_vendidos_business ON pacotes_vendidos (business_id)',
    );
    await txn.execute(
      'CREATE INDEX IF NOT EXISTS idx_pacotes_vendidos_cliente ON pacotes_vendidos (cliente_id)',
    );

    await txn.execute('''
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
    await txn.execute(
      'CREATE INDEX IF NOT EXISTS idx_sessoes_pacotes_vendido ON sessoes_pacotes (pacote_vendido_id)',
    );
    await txn.execute(
      'CREATE INDEX IF NOT EXISTS idx_sessoes_pacotes_data ON sessoes_pacotes (data_agendada)',
    );

    // Estoque Saldos (v33)
    await txn.execute('''
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
    await txn.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_estoque_saldos_uniq 
      ON estoque_saldos (business_id, estoque_id, finalidade, COALESCE(local_id, '')) 
      WHERE deleted_at IS NULL
    ''');

    // Creditos Comerciais e Whatsapp Fila (v34)
    await txn.execute('''
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
    await txn.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_creditos_codigo 
      ON creditos_comerciais (business_id, codigo) 
      WHERE codigo IS NOT NULL AND deleted_at IS NULL
    ''');

    await txn.execute('''
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
    await txn.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_whatsapp_fila_idemp 
      ON whatsapp_fila (business_id, provider, idempotency_key) 
      WHERE idempotency_key IS NOT NULL AND deleted_at IS NULL
    ''');

    // Ativos Imobilizados (v29)
    await txn.execute('''
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
    await txn.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_ativos_imob_estoque_uniq 
      ON ativos_imobilizados (business_id, estoque_id) 
      WHERE deleted_at IS NULL
    ''');
    await txn.execute('''
      CREATE INDEX IF NOT EXISTS idx_ativos_imob_business 
      ON ativos_imobilizados (business_id)
    ''');
  }

  static Future<void> _backfills(Transaction txn) async {
    // Backfill de business_id no estoque herdando de comercio_id
    final estoqueCols = await _getColunas(txn, 'estoque');
    if (estoqueCols.contains('business_id') &&
        estoqueCols.contains('comercio_id')) {
      final affected = await txn.rawUpdate('''
        UPDATE estoque
        SET business_id = comercio_id
        WHERE (business_id IS NULL OR TRIM(business_id) = '')
          AND comercio_id IS NOT NULL 
          AND TRIM(comercio_id) != ''
      ''');
      if (affected > 0) {
        debugPrint(
          'SchemaRepair: estoque.business_id backfill: $affected registros',
        );
      }
    }
  }

  static Future<Set<String>> _getColunas(Transaction txn, String tabela) async {
    try {
      final rows = await txn.rawQuery('PRAGMA table_info($tabela)');
      return rows
          .map((r) => r['name']?.toString().toLowerCase())
          .whereType<String>()
          .toSet();
    } catch (_) {
      return {};
    }
  }

  static Future<void> _addCol(
    Transaction txn,
    String table,
    Set<String> columns,
    String colName,
    String colDef,
  ) async {
    if (!columns.contains(colName.toLowerCase())) {
      await txn.execute('ALTER TABLE $table ADD COLUMN $colName $colDef');
      debugPrint('SchemaRepair: $table.$colName adicionada ($colDef)');
    }
  }
}
