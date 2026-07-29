import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// Pré-homologação: prontuário versionado e exclusão segura de agendamentos.
///
/// A migração é somente aditiva e mantém cópias lógicas antes das alterações.
abstract final class MigrationV13 {
  static Future<void> executar(Database db, {required bool criarBackup}) async {
    if (criarBackup) await _backup(db);

    const colunasAnamnese = <String, String>{
      'criado_por_id': 'TEXT',
      'atualizado_por_id': 'TEXT',
      'versao': 'INTEGER NOT NULL DEFAULT 1',
      'ativa': 'INTEGER NOT NULL DEFAULT 1',
      'agendamento_id': 'TEXT',
      'termo_versao': "TEXT NOT NULL DEFAULT '1.0'",
      'assinatura_tipo': "TEXT NOT NULL DEFAULT 'declaracao_digitada'",
    };
    for (final coluna in colunasAnamnese.entries) {
      await _adicionarColuna(db, 'anamneses', coluna.key, coluna.value);
    }

    const colunasAgendamento = <String, String>{
      'excluido': 'INTEGER NOT NULL DEFAULT 0',
      'excluido_em': 'TEXT',
      'excluido_por_id': 'TEXT',
      'exclusao_motivo': 'TEXT',
    };
    for (final coluna in colunasAgendamento.entries) {
      await _adicionarColuna(db, 'agendamentos', coluna.key, coluna.value);
    }
    await _adicionarColuna(db, 'whatsapp_fila', 'agendamento_id', 'TEXT');

    await db.execute('''CREATE TABLE IF NOT EXISTS agendamento_exclusoes (
      id TEXT PRIMARY KEY,
      comercio_id TEXT NOT NULL,
      agendamento_id TEXT NOT NULL,
      usuario_id TEXT NOT NULL,
      motivo TEXT NOT NULL,
      snapshot_json TEXT NOT NULL,
      vinculos_json TEXT NOT NULL,
      mensagens_canceladas INTEGER NOT NULL DEFAULT 0,
      excluido_em TEXT NOT NULL
    )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_anamneses_versao '
      'ON anamneses(comercio_id, cliente_id, ativa, versao DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_agendamentos_visiveis '
      'ON agendamentos(comercio_id, excluido, inicio)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_agendamento_exclusoes '
      'ON agendamento_exclusoes(comercio_id, agendamento_id, excluido_em)',
    );
  }

  static Future<void> _backup(Database db) async {
    final agora = DateTime.now().toUtc().toIso8601String();
    for (final tabela in ['anamneses', 'agendamentos']) {
      final dados = await db.query(tabela);
      final estrutura = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
        [tabela],
      );
      await db.insert('backups_logicos', {
        'versao_origem': 12,
        'tabela': tabela,
        'estrutura_sql': estrutura.isEmpty ? null : estrutura.first['sql'],
        'dados_json': jsonEncode(dados),
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
    if (!colunas.any((item) => item['name'] == coluna)) {
      await db.execute('ALTER TABLE $tabela ADD COLUMN $coluna $definicao');
    }
  }
}
