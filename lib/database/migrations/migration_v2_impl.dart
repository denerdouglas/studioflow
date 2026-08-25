import 'dart:convert';

import 'package:sqflite/sqflite.dart';

abstract final class MigrationV2 {
  static const String comercioLegado = 'comercio_legado';

  static Future<void> executar(Database db, {required bool criarBackup}) async {
    await _criarTabelaBackups(db);
    if (criarBackup) {
      await _criarBackupLogico(db);
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS comercios (
        id TEXT PRIMARY KEY,
        codigo_acesso TEXT NOT NULL UNIQUE,
        nome TEXT NOT NULL,
        nome_exibicao TEXT NOT NULL,
        responsavel TEXT NOT NULL,
        telefone TEXT NOT NULL,
        email TEXT NOT NULL,
        ativo INTEGER NOT NULL DEFAULT 1,
        modulo_loja_ativo INTEGER NOT NULL DEFAULT 1,
        modulo_servicos_ativo INTEGER NOT NULL DEFAULT 1,
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS usuarios (
        id TEXT PRIMARY KEY,
        comercio_id TEXT NOT NULL,
        profissional_id TEXT,
        nome TEXT NOT NULL,
        telefone TEXT NOT NULL,
        email_login TEXT NOT NULL,
        senha_hash TEXT NOT NULL,
        senha_salt TEXT NOT NULL,
        funcao TEXT NOT NULL,
        ativo INTEGER NOT NULL DEFAULT 1,
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL,
        UNIQUE (comercio_id, email_login),
        FOREIGN KEY (comercio_id) REFERENCES comercios (id) ON DELETE CASCADE,
        FOREIGN KEY (profissional_id) REFERENCES profissionais (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS permissoes (
        usuario_id TEXT NOT NULL,
        modulo TEXT NOT NULL,
        permitido INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (usuario_id, modulo),
        FOREIGN KEY (usuario_id) REFERENCES usuarios (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sessoes (
        id TEXT PRIMARY KEY,
        usuario_id TEXT NOT NULL,
        comercio_id TEXT NOT NULL,
        criada_em TEXT NOT NULL,
        ultimo_acesso TEXT NOT NULL,
        persistente INTEGER NOT NULL DEFAULT 0,
        ativa INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (usuario_id) REFERENCES usuarios (id) ON DELETE CASCADE,
        FOREIGN KEY (comercio_id) REFERENCES comercios (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_usuarios_comercio
      ON usuarios (comercio_id, ativo)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sessoes_ativas
      ON sessoes (ativa, persistente)
    ''');

    const tabelasComComercio = <String>[
      'clientes',
      'anamneses',
      'profissionais',
      'servicos',
      'agendamentos',
      'estoque',
      'movimentacoes_estoque',
      'manutencoes',
      'movimentacoes_financeiras',
      'comissoes',
      'configuracoes',
      'notificacoes',
    ];

    for (final tabela in tabelasComComercio) {
      if (await _tabelaExiste(db, tabela) &&
          !await _colunaExiste(db, tabela, 'comercio_id')) {
        await db.execute(
          "ALTER TABLE $tabela ADD COLUMN comercio_id TEXT NOT NULL DEFAULT '$comercioLegado'",
        );
      }
    }
  }

  static Future<void> _criarTabelaBackups(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS backups_logicos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        versao_origem INTEGER NOT NULL,
        tabela TEXT NOT NULL,
        estrutura_sql TEXT,
        dados_json TEXT NOT NULL,
        criado_em TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _criarBackupLogico(Database db) async {
    final tabelas = await db.rawQuery('''
      SELECT name, sql
      FROM sqlite_master
      WHERE type = 'table'
        AND name NOT LIKE 'sqlite_%'
        AND name != 'backups_logicos'
      ORDER BY name
    ''');
    final agora = DateTime.now().toUtc().toIso8601String();

    for (final tabela in tabelas) {
      final nome = tabela['name'] as String;
      final registros = await db.query(nome);
      await db.insert('backups_logicos', {
        'versao_origem': 1,
        'tabela': nome,
        'estrutura_sql': tabela['sql'] as String?,
        'dados_json': jsonEncode(registros),
        'criado_em': agora,
      });
    }
  }

  static Future<bool> _tabelaExiste(Database db, String tabela) async {
    final resultado = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
      [tabela],
    );
    return resultado.isNotEmpty;
  }

  static Future<bool> _colunaExiste(
    Database db,
    String tabela,
    String coluna,
  ) async {
    final colunas = await db.rawQuery('PRAGMA table_info($tabela)');
    return colunas.any((item) => item['name'] == coluna);
  }
}
