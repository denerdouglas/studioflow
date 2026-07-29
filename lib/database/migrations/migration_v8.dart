import 'dart:convert';

import 'package:sqflite/sqflite.dart';

abstract final class MigrationV8 {
  static Future<void> executar(Database db, {required bool criarBackup}) async {
    if (criarBackup) await _backup(db);

    const comercio = <String, String>{
      'tipo_estabelecimento': "TEXT NOT NULL DEFAULT 'salao'",
      'logo_path': 'TEXT',
      'cor_principal': "TEXT NOT NULL DEFAULT '#70569A'",
      'cor_secundaria': "TEXT NOT NULL DEFAULT '#8B5CF6'",
      'cor_destaque': "TEXT NOT NULL DEFAULT '#D9C7F2'",
      'tema_modo': "TEXT NOT NULL DEFAULT 'claro'",
      'tema_automatico': 'INTEGER NOT NULL DEFAULT 1',
    };
    for (final coluna in comercio.entries) {
      await _adicionarColuna(db, 'comercios', coluna.key, coluna.value);
    }

    await db.execute('''CREATE TABLE IF NOT EXISTS recuperacoes_senha (
      id TEXT PRIMARY KEY,
      usuario_id TEXT NOT NULL,
      comercio_id TEXT NOT NULL,
      metodo TEXT NOT NULL,
      sucesso INTEGER NOT NULL DEFAULT 0,
      criado_em TEXT NOT NULL,
      FOREIGN KEY (usuario_id) REFERENCES usuarios(id) ON DELETE CASCADE,
      FOREIGN KEY (comercio_id) REFERENCES comercios(id) ON DELETE CASCADE
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS dispositivos_sincronizacao (
      id TEXT PRIMARY KEY,
      comercio_id TEXT NOT NULL,
      usuario_id TEXT NOT NULL,
      apelido TEXT NOT NULL,
      ultimo_acesso TEXT NOT NULL,
      sincronizacao_ativa INTEGER NOT NULL DEFAULT 0,
      provedor TEXT NOT NULL DEFAULT 'nenhum',
      FOREIGN KEY (usuario_id) REFERENCES usuarios(id) ON DELETE CASCADE,
      FOREIGN KEY (comercio_id) REFERENCES comercios(id) ON DELETE CASCADE
    )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_usuarios_login_global '
      'ON usuarios(LOWER(email_login), ativo)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_recuperacoes_usuario '
      'ON recuperacoes_senha(usuario_id, criado_em)',
    );
  }

  static Future<void> _backup(Database db) async {
    final agora = DateTime.now().toUtc().toIso8601String();
    for (final tabela in <String>[
      'comercios',
      'usuarios',
      'permissoes',
      'permissoes_acoes',
      'sessoes',
      'configuracoes',
      'integracoes_configuracao',
    ]) {
      final estrutura = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
        [tabela],
      );
      if (estrutura.isEmpty) continue;
      await db.insert('backups_logicos', {
        'versao_origem': 7,
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
