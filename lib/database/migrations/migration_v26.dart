import 'package:sqflite/sqflite.dart';

abstract final class MigrationV26 {
  static Future<void> executar(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS catalogos_loja (
      id TEXT PRIMARY KEY,
      comercio_id TEXT NOT NULL,
      unidade_id TEXT,
      nome TEXT NOT NULL,
      descricao TEXT,
      imagem_capa TEXT,
      icone TEXT,
      tipo_controle TEXT NOT NULL,
      ativo INTEGER NOT NULL DEFAULT 1,
      ordem INTEGER NOT NULL DEFAULT 0,
      criado_em TEXT NOT NULL,
      atualizado_em TEXT NOT NULL,
      UNIQUE(comercio_id, unidade_id, nome)
    )''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_catalogos_loja_exibicao
      ON catalogos_loja(comercio_id, unidade_id, ativo, ordem, nome)''');

    await _addColumn(db, 'estoque', 'catalogo_id', 'TEXT');
    await _addColumn(db, 'estoque', 'tamanho', 'TEXT');
    await _addColumn(db, 'estoque', 'cor', 'TEXT');
    await _addColumn(db, 'estoque', 'variacao', 'TEXT');
    await _addColumn(
      db,
      'estoque',
      'tipo_controle',
      "TEXT NOT NULL DEFAULT 'produto_comum'",
    );
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_estoque_catalogo
      ON estoque(comercio_id, catalogo_id, ativo, nome)''');

    await db.execute('''CREATE TABLE IF NOT EXISTS catalogo_loja_auditoria (
      id TEXT PRIMARY KEY,
      comercio_id TEXT NOT NULL,
      unidade_id TEXT,
      catalogo_id TEXT,
      produto_id TEXT,
      usuario_id TEXT NOT NULL,
      acao TEXT NOT NULL,
      estado_anterior TEXT,
      estado_novo TEXT,
      reversao_de TEXT,
      criado_em TEXT NOT NULL
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS undo_auditoria (
      id TEXT PRIMARY KEY,
      comercio_id TEXT NOT NULL,
      unidade_id TEXT,
      usuario_id TEXT NOT NULL,
      entidade TEXT NOT NULL,
      entidade_id TEXT NOT NULL,
      acao TEXT NOT NULL,
      estado_anterior TEXT,
      estado_novo TEXT,
      revertida INTEGER NOT NULL DEFAULT 0,
      revertida_em TEXT,
      criado_em TEXT NOT NULL
    )''');
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
