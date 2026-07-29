import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../models/domain/mensagem_modelo.dart';

abstract final class MigrationV7 {
  static Future<void> executar(Database db, {required bool criarBackup}) async {
    if (criarBackup) await _backup(db);

    const colunasPagamento = <String, String>{
      'banco': "TEXT NOT NULL DEFAULT ''",
      'observacoes': "TEXT NOT NULL DEFAULT ''",
      'formas_aceitas': "TEXT NOT NULL DEFAULT '[\"pix\",\"dinheiro\"]'",
      'valor_sinal_fixo': 'REAL NOT NULL DEFAULT 0',
      'percentual_sinal': 'REAL NOT NULL DEFAULT 0',
    };
    for (final coluna in colunasPagamento.entries) {
      await _adicionarColuna(
        db,
        'configuracoes_pagamento',
        coluna.key,
        coluna.value,
      );
    }

    await db.execute('''CREATE TABLE IF NOT EXISTS modelos_mensagens (
      id TEXT PRIMARY KEY,
      comercio_id TEXT NOT NULL,
      chave TEXT NOT NULL,
      nome TEXT NOT NULL,
      texto TEXT NOT NULL,
      texto_padrao TEXT NOT NULL,
      ativo INTEGER NOT NULL DEFAULT 1,
      origem_id TEXT,
      criado_em TEXT NOT NULL,
      atualizado_em TEXT NOT NULL,
      UNIQUE(comercio_id, chave)
    )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_modelos_mensagens_comercio ON modelos_mensagens(comercio_id, ativo, nome)',
    );

    final comercios = await db.query('comercios', columns: ['id']);
    final agora = DateTime.now().toUtc().toIso8601String();
    for (final comercio in comercios) {
      final comercioId = comercio['id'] as String;
      for (final modelo in modelosMensagensPadrao.entries) {
        await db.insert('modelos_mensagens', {
          'id': 'modelo_${comercioId}_${modelo.key}',
          'comercio_id': comercioId,
          'chave': modelo.key,
          'nome': modelo.value.nome,
          'texto': modelo.value.texto,
          'texto_padrao': modelo.value.texto,
          'ativo': 1,
          'criado_em': agora,
          'atualizado_em': agora,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
  }

  static Future<void> _backup(Database db) async {
    final agora = DateTime.now().toUtc().toIso8601String();
    for (final tabela in <String>[
      'configuracoes',
      'configuracoes_pagamento',
      'clientes',
      'agendamentos',
      'vendas',
      'venda_itens',
      'movimentacoes_financeiras',
      'sessoes',
    ]) {
      final existe = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
        [tabela],
      );
      if (existe.isEmpty) continue;
      await db.insert('backups_logicos', {
        'versao_origem': 6,
        'tabela': tabela,
        'estrutura_sql': existe.first['sql'],
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
