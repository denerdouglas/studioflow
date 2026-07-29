import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// Agenda persistente de contatos de aniversário.
/// A migração é estritamente aditiva e preserva um backup lógico dos clientes.
abstract final class MigrationV12 {
  static Future<void> executar(Database db, {required bool criarBackup}) async {
    if (criarBackup) await _backup(db);
    await db.execute('''CREATE TABLE IF NOT EXISTS contatos_agendados (
      id TEXT PRIMARY KEY,
      comercio_id TEXT NOT NULL,
      cliente_id TEXT NOT NULL,
      tipo TEXT NOT NULL DEFAULT 'aniversario',
      agendado_para TEXT NOT NULL,
      observacao TEXT NOT NULL DEFAULT '',
      status TEXT NOT NULL DEFAULT 'pendente'
        CHECK (status IN ('pendente','concluido','cancelado')),
      criado_por_id TEXT NOT NULL,
      criado_em TEXT NOT NULL,
      atualizado_em TEXT NOT NULL,
      FOREIGN KEY (comercio_id) REFERENCES comercios(id) ON DELETE CASCADE,
      FOREIGN KEY (cliente_id) REFERENCES clientes(id) ON DELETE CASCADE
    )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_contatos_agendados_pendentes '
      'ON contatos_agendados(comercio_id, status, agendado_para)',
    );
  }

  static Future<void> _backup(Database db) async {
    final data = await db.query('clientes');
    final structure = await db.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type='table' AND name='clientes'",
    );
    await db.insert('backups_logicos', {
      'versao_origem': 11,
      'tabela': 'clientes',
      'estrutura_sql': structure.isEmpty ? null : structure.first['sql'],
      'dados_json': jsonEncode(data),
      'criado_em': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
