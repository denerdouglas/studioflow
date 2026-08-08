import 'package:sqflite/sqflite.dart';

abstract final class MigrationV34 {
  static Future<void> executar(Database db) async {
    // 1. Criar creditos_comerciais
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
    
    // Garantir que whatsapp_fila exista
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

    // 2. Agendamentos
    await _garantirColunasAgendamentos(db);
    
    // 3. Whatsapp Fila
    await _garantirColunasWhatsappFila(db);
  }

  static Future<void> _addColumn(
    Database db,
    String table,
    String column,
    String type,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final hasColumn = columns.any((c) => c['name'] == column);
    if (!hasColumn) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    }
  }

  static Future<void> _garantirColunasAgendamentos(Database db) async {
    await _addColumn(db, 'agendamentos', 'unidade_id', 'TEXT');
    await _addColumn(db, 'agendamentos', 'filial_id', 'TEXT');
    await _addColumn(db, 'agendamentos', 'sala_id', 'TEXT');
    await _addColumn(db, 'agendamentos', 'cadeira_id', 'TEXT');
    await _addColumn(db, 'agendamentos', 'mesa_id', 'TEXT');
    await _addColumn(db, 'agendamentos', 'cabine_id', 'TEXT');
    await _addColumn(db, 'agendamentos', 'equipamento_id', 'TEXT');
    await _addColumn(db, 'agendamentos', 'tempo_real', 'INTEGER');
    await _addColumn(db, 'agendamentos', 'modalidade_origem', 'TEXT');
    // Adicionais faltantes caso a v30 e v33 nao executem por completo:
    await _addColumn(db, 'agendamentos', 'business_id', 'TEXT');
    await _addColumn(db, 'agendamentos', 'encaixe', 'INTEGER DEFAULT 0');
    await _addColumn(db, 'agendamentos', 'grupo_agendamento_id', 'TEXT');
    await _addColumn(db, 'agendamentos', 'ordem_no_grupo', 'INTEGER');
  }

  static Future<void> _garantirColunasWhatsappFila(Database db) async {
    await _addColumn(db, 'whatsapp_fila', 'business_id', 'TEXT');
    await _addColumn(db, 'whatsapp_fila', 'comercio_id', 'TEXT');
    await _addColumn(db, 'whatsapp_fila', 'cliente_id', 'TEXT');
    await _addColumn(db, 'whatsapp_fila', 'agendamento_id', 'TEXT');
    await _addColumn(db, 'whatsapp_fila', 'idempotency_key', 'TEXT');
    await _addColumn(db, 'whatsapp_fila', 'provider', 'TEXT');
    await _addColumn(db, 'whatsapp_fila', 'provider_message_id', 'TEXT');
    await _addColumn(db, 'whatsapp_fila', 'conversation_id', 'TEXT');
    await _addColumn(db, 'whatsapp_fila', 'template_id', 'TEXT');
    await _addColumn(db, 'whatsapp_fila', 'template', 'TEXT');
    await _addColumn(db, 'whatsapp_fila', 'payload', 'TEXT');
    await _addColumn(db, 'whatsapp_fila', 'payload_json', 'TEXT');
    await _addColumn(db, 'whatsapp_fila', 'attempt', 'INTEGER DEFAULT 0');
    await _addColumn(db, 'whatsapp_fila', 'erro', 'TEXT');
    await _addColumn(db, 'whatsapp_fila', 'latencia', 'INTEGER');
    await _addColumn(db, 'whatsapp_fila', 'scheduled_at', 'TEXT');
    await _addColumn(db, 'whatsapp_fila', 'sent_at', 'TEXT');
    await _addColumn(db, 'whatsapp_fila', 'delivered_at', 'TEXT');
    await _addColumn(db, 'whatsapp_fila', 'read_at', 'TEXT');
    await _addColumn(db, 'whatsapp_fila', 'failed_at', 'TEXT');
    await _addColumn(db, 'whatsapp_fila', 'last_attempt_at', 'TEXT');
    await _addColumn(db, 'whatsapp_fila', 'created_at', 'TEXT');
    await _addColumn(db, 'whatsapp_fila', 'criado_em', 'TEXT');
    await _addColumn(db, 'whatsapp_fila', 'updated_at', 'TEXT');
    await _addColumn(db, 'whatsapp_fila', 'atualizado_em', 'TEXT');
    await _addColumn(db, 'whatsapp_fila', 'deleted_at', 'TEXT');
    await _addColumn(db, 'whatsapp_fila', 'created_by', 'TEXT');
    await _addColumn(db, 'whatsapp_fila', 'updated_by', 'TEXT');

    final columns = await db.rawQuery('PRAGMA table_info(whatsapp_fila)');
    
    // Backfill para manter consistência sem dropar/apagar colunas velhas
    final hasBusinessId = columns.any((c) => c['name'] == 'business_id');
    final hasComercioId = columns.any((c) => c['name'] == 'comercio_id');
    if (hasBusinessId && hasComercioId) {
      await db.execute('''
        UPDATE whatsapp_fila
        SET business_id = comercio_id
        WHERE (business_id IS NULL OR business_id = '')
          AND comercio_id IS NOT NULL
      ''');
    }

    final hasCreatedAt = columns.any((c) => c['name'] == 'created_at');
    final hasCriadoEm = columns.any((c) => c['name'] == 'criado_em');
    if (hasCreatedAt && hasCriadoEm) {
      await db.execute('''
        UPDATE whatsapp_fila
        SET created_at = criado_em
        WHERE (created_at IS NULL OR created_at = '')
          AND criado_em IS NOT NULL
      ''');
    }

    final hasUpdatedAt = columns.any((c) => c['name'] == 'updated_at');
    final hasAtualizadoEm = columns.any((c) => c['name'] == 'atualizado_em');
    if (hasUpdatedAt && hasAtualizadoEm) {
      await db.execute('''
        UPDATE whatsapp_fila
        SET updated_at = atualizado_em
        WHERE (updated_at IS NULL OR updated_at = '')
          AND atualizado_em IS NOT NULL
      ''');
    }

    final hasPayload = columns.any((c) => c['name'] == 'payload');
    final hasPayloadJson = columns.any((c) => c['name'] == 'payload_json');
    if (hasPayload && hasPayloadJson) {
      await db.execute('''
        UPDATE whatsapp_fila
        SET payload = payload_json
        WHERE (payload IS NULL OR payload = '')
          AND payload_json IS NOT NULL
      ''');
    }

    final hasTemplateId = columns.any((c) => c['name'] == 'template_id');
    final hasTemplate = columns.any((c) => c['name'] == 'template');
    if (hasTemplateId && hasTemplate) {
      await db.execute('''
        UPDATE whatsapp_fila
        SET template_id = template
        WHERE (template_id IS NULL OR template_id = '')
          AND template IS NOT NULL
      ''');
    }
  }
}
