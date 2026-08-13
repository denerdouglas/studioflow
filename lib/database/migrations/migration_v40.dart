import 'package:sqflite/sqflite.dart';

abstract final class MigrationV40 {
  static Future<void> executar(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS consignacao_conferencias (
      id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL,
      consignacao_id TEXT NOT NULL, finalidade TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'em_andamento', esperado INTEGER NOT NULL,
      conferido INTEGER NOT NULL DEFAULT 0, pendente INTEGER NOT NULL,
      iniciado_em TEXT NOT NULL, finalizado_em TEXT,
      responsavel_id TEXT NOT NULL, observacao TEXT,
      criado_em TEXT NOT NULL, atualizado_em TEXT NOT NULL,
      CHECK(finalidade IN ('recebimento','inventario','devolucao')),
      CHECK(status IN ('em_andamento','pausada','finalizada','cancelada')),
      FOREIGN KEY(consignacao_id) REFERENCES consignacoes(id) ON DELETE RESTRICT
    )''');
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS consignacao_conferencia_itens (
      id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL,
      conferencia_id TEXT NOT NULL, peca_unica_id TEXT NOT NULL,
      resultado TEXT NOT NULL DEFAULT 'conferida', leitura_original TEXT,
      observacao TEXT, responsavel_id TEXT NOT NULL, registrado_em TEXT NOT NULL,
      UNIQUE(conferencia_id, peca_unica_id),
      FOREIGN KEY(conferencia_id) REFERENCES consignacao_conferencias(id) ON DELETE RESTRICT,
      FOREIGN KEY(peca_unica_id) REFERENCES pecas_unicas(id) ON DELETE RESTRICT
    )''',
    );
    await db.execute('''CREATE TABLE IF NOT EXISTS consignacao_acertos (
      id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL,
      consignacao_id TEXT NOT NULL, quantidade_recebida INTEGER NOT NULL,
      quantidade_vendida INTEGER NOT NULL, quantidade_devolvida INTEGER NOT NULL,
      quantidade_perdas INTEGER NOT NULL DEFAULT 0,
      valor_vendido_sistema REAL NOT NULL DEFAULT 0,
      quantidade_fornecedor INTEGER, valor_fornecedor REAL,
      comissao_percentual REAL, comissao_valor REAL NOT NULL DEFAULT 0,
      repasse REAL NOT NULL DEFAULT 0, desconto REAL NOT NULL DEFAULT 0,
      taxas REAL NOT NULL DEFAULT 0, ajustes REAL NOT NULL DEFAULT 0,
      perdas_financeiras REAL NOT NULL DEFAULT 0,
      resultado_liquido REAL NOT NULL DEFAULT 0,
      divergencia_quantidade INTEGER, divergencia_valor REAL,
      divergencia_confirmada INTEGER NOT NULL DEFAULT 0,
      data_acerto TEXT, data_pagamento TEXT, observacoes TEXT,
      status TEXT NOT NULL DEFAULT 'em_aberto', responsavel_id TEXT NOT NULL,
      criado_em TEXT NOT NULL, atualizado_em TEXT NOT NULL,
      UNIQUE(comercio_id, consignacao_id),
      CHECK(status IN ('em_aberto','em_conferencia','conferido','pago','fechado')),
      FOREIGN KEY(consignacao_id) REFERENCES consignacoes(id) ON DELETE RESTRICT
    )''');
    await _addColumn(
      db,
      'consignacoes',
      'acerto_status',
      "TEXT NOT NULL DEFAULT 'em_aberto'",
    );
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_conf_remessa_status
      ON consignacao_conferencias(comercio_id,consignacao_id,status)''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_conf_item_codigo
      ON consignacao_conferencia_itens(conferencia_id,peca_unica_id)''');
  }

  static Future<void> _addColumn(
    DatabaseExecutor db,
    String table,
    String column,
    String definition,
  ) async {
    final tableExists =
        Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=?",
            [table],
          ),
        ) ??
        0;
    if (tableExists == 0) return;
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (!columns.any((row) => row['name'] == column)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }
}
