import 'dart:convert';

import 'package:sqflite/sqflite.dart';

abstract final class MigrationV15 {
  static Future<void> executar(Database db, {required bool criarBackup}) async {
    if (criarBackup) {
      final agora = DateTime.now().toUtc().toIso8601String();
      final dados = await db.query('anamneses');
      final estrutura = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='anamneses'",
      );
      if (estrutura.isNotEmpty) {
        await db.insert('backups_logicos', {
          'versao_origem': 14,
          'tabela': 'anamneses',
          'estrutura_sql': estrutura.first['sql'],
          'dados_json': jsonEncode(dados),
          'criado_em': agora,
        });
      }
    }

    const colunasAnamnese = <String, String>{
      'versao': 'INTEGER NOT NULL DEFAULT 1',
      'ativa': 'INTEGER NOT NULL DEFAULT 1',
      'termo_versao': "TEXT NOT NULL DEFAULT '1.0'",
      'assinatura_tipo': "TEXT NOT NULL DEFAULT 'declaracao_digitada'",
      'criado_por_id': 'TEXT',
      'atualizado_por_id': 'TEXT',
      'agendamento_id': 'TEXT',
    };

    for (final item in colunasAnamnese.entries) {
      await _adicionarColuna(db, 'anamneses', item.key, item.value);
    }

    // Invalidate old active anamneses logic if needed, but defaults will handle them.
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_anamneses_ativa ON anamneses(comercio_id, cliente_id, ativa, versao DESC)',
    );
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
