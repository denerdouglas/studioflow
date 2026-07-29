import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// Trilha explícita para transferências entre os estoques do salão e da loja.
abstract final class MigrationV10 {
  static Future<void> executar(Database db, {required bool criarBackup}) async {
    if (criarBackup) await _backup(db);
    await db.execute('''CREATE TABLE IF NOT EXISTS transferencias_estoque (
      id TEXT PRIMARY KEY,
      comercio_id TEXT NOT NULL,
      produto_origem_id TEXT NOT NULL,
      produto_destino_id TEXT NOT NULL,
      origem TEXT NOT NULL CHECK (origem IN ('salao', 'loja')),
      destino TEXT NOT NULL CHECK (destino IN ('salao', 'loja')),
      quantidade REAL NOT NULL CHECK (quantidade > 0),
      motivo TEXT NOT NULL,
      usuario_id TEXT NOT NULL,
      criado_em TEXT NOT NULL,
      CHECK (origem <> destino),
      FOREIGN KEY (comercio_id) REFERENCES comercios(id) ON DELETE CASCADE,
      FOREIGN KEY (produto_origem_id) REFERENCES estoque(id),
      FOREIGN KEY (produto_destino_id) REFERENCES estoque(id),
      FOREIGN KEY (usuario_id) REFERENCES usuarios(id)
    )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transferencias_comercio '
      'ON transferencias_estoque(comercio_id, criado_em)',
    );
  }

  static Future<void> _backup(Database db) async {
    final now = DateTime.now().toUtc().toIso8601String();
    for (final table in <String>[
      'estoque',
      'movimentacoes_estoque',
      'ofertas_reposicao',
      'catalogo_produtos',
      'catalogo_sugestoes',
    ]) {
      final data = await db.query(table);
      final structure = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
        [table],
      );
      await db.insert('backups_logicos', {
        'versao_origem': 9,
        'tabela': table,
        'estrutura_sql': structure.isEmpty ? null : structure.first['sql'],
        'dados_json': jsonEncode(data),
        'criado_em': now,
      });
    }
  }
}
