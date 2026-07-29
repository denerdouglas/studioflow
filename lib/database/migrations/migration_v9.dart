import 'dart:convert';

import 'package:sqflite/sqflite.dart';

abstract final class MigrationV9 {
  static Future<void> executar(Database db, {required bool criarBackup}) async {
    if (criarBackup) await _backup(db);

    const integracoes = <String, String>{
      'ultimo_cursor': 'INTEGER NOT NULL DEFAULT 0',
      'ultima_sincronizacao': 'TEXT',
      'ultimo_erro': 'TEXT',
    };
    for (final coluna in integracoes.entries) {
      await _adicionarColuna(
        db,
        'integracoes_configuracao',
        coluna.key,
        coluna.value,
      );
    }

    const fila = <String, String>{
      'versao_servidor': 'INTEGER NOT NULL DEFAULT 0',
      'proxima_tentativa': 'TEXT',
      'sincronizada_em': 'TEXT',
    };
    for (final coluna in fila.entries) {
      await _adicionarColuna(
        db,
        'fila_sincronizacao',
        coluna.key,
        coluna.value,
      );
    }

    await db.execute('''CREATE TABLE IF NOT EXISTS conflitos_sincronizacao (
      id TEXT PRIMARY KEY,
      comercio_id TEXT NOT NULL,
      operacao_id TEXT NOT NULL,
      entidade TEXT NOT NULL,
      entidade_id TEXT NOT NULL,
      versao_local INTEGER NOT NULL,
      versao_servidor INTEGER NOT NULL,
      payload_local TEXT NOT NULL,
      payload_servidor TEXT,
      status TEXT NOT NULL DEFAULT 'pendente',
      criado_em TEXT NOT NULL,
      resolvido_em TEXT,
      UNIQUE(comercio_id, operacao_id),
      FOREIGN KEY (comercio_id) REFERENCES comercios(id) ON DELETE CASCADE
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS alteracoes_remotas (
      comercio_id TEXT NOT NULL,
      cursor INTEGER NOT NULL,
      entidade TEXT NOT NULL,
      entidade_id TEXT NOT NULL,
      versao_servidor INTEGER NOT NULL,
      excluido INTEGER NOT NULL DEFAULT 0,
      payload_json TEXT NOT NULL,
      recebido_em TEXT NOT NULL,
      aplicado_em TEXT,
      erro TEXT,
      PRIMARY KEY (comercio_id, cursor),
      FOREIGN KEY (comercio_id) REFERENCES comercios(id) ON DELETE CASCADE
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS registro_sync_estado (
      comercio_id TEXT NOT NULL,
      entidade TEXT NOT NULL,
      entidade_id TEXT NOT NULL,
      hash_local TEXT,
      versao_servidor INTEGER NOT NULL DEFAULT 0,
      atualizado_em TEXT NOT NULL,
      PRIMARY KEY (comercio_id, entidade, entidade_id),
      FOREIGN KEY (comercio_id) REFERENCES comercios(id) ON DELETE CASCADE
    )''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_fila_retry
      ON fila_sincronizacao(comercio_id, status, proxima_tentativa)''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_conflitos_pendentes
      ON conflitos_sincronizacao(comercio_id, status, criado_em)''');
  }

  static Future<void> _backup(Database db) async {
    final agora = DateTime.now().toUtc().toIso8601String();
    for (final tabela in <String>[
      'integracoes_configuracao',
      'fila_sincronizacao',
      'dispositivos_sincronizacao',
      'sessoes',
      'comercios',
      'usuarios',
    ]) {
      final estrutura = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
        [tabela],
      );
      if (estrutura.isEmpty) continue;
      await db.insert('backups_logicos', {
        'versao_origem': 8,
        'tabela': tabela,
        'estrutura_sql': estrutura.first['sql'],
        'dados_json': jsonEncode(await db.query(tabela)),
        'criado_em': agora,
      });
    }
  }

  static Future<void> _adicionarColuna(
    Database db,
    String tabela,
    String coluna,
    String definicao,
  ) async {
    final colunas = await db.rawQuery('PRAGMA table_info($tabela)');
    if (colunas.any((item) => item['name'] == coluna)) return;
    await db.execute('ALTER TABLE $tabela ADD COLUMN $coluna $definicao');
  }
}
