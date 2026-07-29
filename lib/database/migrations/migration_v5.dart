import 'dart:convert';

import 'package:sqflite/sqflite.dart';

abstract final class MigrationV5 {
  static const _acoes = <String>[
    'visualizarEstoque',
    'visualizarCusto',
    'cadastrarProduto',
    'editarProduto',
    'movimentarEstoque',
    'realizarVenda',
    'aplicarDesconto',
    'cancelarVenda',
    'cadastrarFornecedor',
    'criarPedido',
    'aprovarPedido',
    'receberPedido',
    'acessarConsignacao',
    'acessarRelatorios',
    'configurarIa',
    'visualizarConversas',
    'configurarPix',
    'gerenciarAgenda',
    'acessarFinanceiro',
  ];

  static Future<void> executar(Database db, {required bool criarBackup}) async {
    if (criarBackup) await _backup(db);

    await db.execute('''CREATE TABLE IF NOT EXISTS permissoes_acoes (
      usuario_id TEXT NOT NULL,
      comercio_id TEXT NOT NULL,
      acao TEXT NOT NULL,
      permitido INTEGER NOT NULL DEFAULT 0,
      atualizado_em TEXT NOT NULL,
      PRIMARY KEY (usuario_id, acao),
      FOREIGN KEY (usuario_id) REFERENCES usuarios(id) ON DELETE CASCADE,
      FOREIGN KEY (comercio_id) REFERENCES comercios(id) ON DELETE CASCADE
    )''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_permissoes_acoes_comercio
      ON permissoes_acoes(comercio_id, usuario_id, permitido)''');

    await db.execute('''CREATE TABLE IF NOT EXISTS unidades (
      id TEXT PRIMARY KEY,
      comercio_id TEXT NOT NULL,
      nome TEXT NOT NULL,
      codigo TEXT NOT NULL,
      principal INTEGER NOT NULL DEFAULT 0,
      ativo INTEGER NOT NULL DEFAULT 1,
      criado_em TEXT NOT NULL,
      atualizado_em TEXT NOT NULL,
      UNIQUE(comercio_id, codigo),
      FOREIGN KEY (comercio_id) REFERENCES comercios(id) ON DELETE CASCADE
    )''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_unidades_comercio
      ON unidades(comercio_id, ativo)''');

    await db.execute('''CREATE TABLE IF NOT EXISTS fila_sincronizacao (
      id TEXT PRIMARY KEY,
      comercio_id TEXT NOT NULL,
      unidade_id TEXT,
      entidade TEXT NOT NULL,
      entidade_id TEXT NOT NULL,
      operacao TEXT NOT NULL,
      payload_json TEXT NOT NULL,
      versao_local INTEGER NOT NULL DEFAULT 1,
      status TEXT NOT NULL DEFAULT 'pendente',
      tentativas INTEGER NOT NULL DEFAULT 0,
      ultimo_erro TEXT,
      criada_em TEXT NOT NULL,
      atualizada_em TEXT NOT NULL,
      FOREIGN KEY (comercio_id) REFERENCES comercios(id) ON DELETE CASCADE,
      FOREIGN KEY (unidade_id) REFERENCES unidades(id)
    )''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_fila_sincronizacao
      ON fila_sincronizacao(comercio_id, status, criada_em)''');

    await db.execute('''CREATE TABLE IF NOT EXISTS integracoes_configuracao (
      comercio_id TEXT PRIMARY KEY,
      provedor_backend TEXT NOT NULL DEFAULT 'nenhum',
      endpoint_publico TEXT,
      sincronizacao_ativa INTEGER NOT NULL DEFAULT 0,
      atualizado_em TEXT NOT NULL,
      FOREIGN KEY (comercio_id) REFERENCES comercios(id) ON DELETE CASCADE
    )''');

    final agora = DateTime.now().toUtc().toIso8601String();
    await db.rawInsert(
      '''INSERT OR IGNORE INTO unidades
      (id, comercio_id, nome, codigo, principal, ativo, criado_em, atualizado_em)
      SELECT 'uni_' || id, id, 'Unidade principal', 'MATRIZ', 1, 1, ?, ?
      FROM comercios''',
      [agora, agora],
    );
    await db.rawInsert(
      '''INSERT OR IGNORE INTO integracoes_configuracao
      (comercio_id, provedor_backend, sincronizacao_ativa, atualizado_em)
      SELECT id, 'nenhum', 0, ? FROM comercios''',
      [agora],
    );

    final usuarios = await db.query(
      'usuarios',
      columns: ['id', 'comercio_id', 'funcao'],
    );
    for (final usuario in usuarios) {
      final id = usuario['id'] as String;
      final comercioId = usuario['comercio_id'] as String;
      final funcao = usuario['funcao'] as String;
      final modulos = (await db.query(
        'permissoes',
        columns: ['modulo'],
        where: 'usuario_id = ? AND permitido = 1',
        whereArgs: [id],
      )).map((item) => item['modulo'] as String).toSet();
      for (final acao in _acoes) {
        await db.insert('permissoes_acoes', {
          'usuario_id': id,
          'comercio_id': comercioId,
          'acao': acao,
          'permitido': _permitirLegado(funcao, modulos, acao) ? 1 : 0,
          'atualizado_em': agora,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
  }

  static bool _permitirLegado(String funcao, Set<String> modulos, String acao) {
    if (funcao == 'dono') return true;
    return switch (acao) {
      'visualizarEstoque' ||
      'cadastrarProduto' ||
      'editarProduto' ||
      'movimentarEstoque' => modulos.contains('estoque'),
      'visualizarCusto' =>
        funcao == 'gerente' &&
            (modulos.contains('estoque') || modulos.contains('financeiro')),
      'realizarVenda' || 'aplicarDesconto' =>
        modulos.contains('lojaSalao') || modulos.contains('caixa'),
      'cancelarVenda' ||
      'aprovarPedido' => funcao == 'gerente' && modulos.contains('lojaSalao'),
      'cadastrarFornecedor' ||
      'criarPedido' ||
      'receberPedido' ||
      'acessarConsignacao' => modulos.contains('lojaSalao'),
      'acessarRelatorios' => modulos.contains('relatorios'),
      'configurarIa' ||
      'visualizarConversas' => modulos.contains('configuracoes'),
      'configurarPix' || 'acessarFinanceiro' => modulos.contains('financeiro'),
      'gerenciarAgenda' => modulos.contains('agenda'),
      _ => false,
    };
  }

  static Future<void> _backup(Database db) async {
    final agora = DateTime.now().toUtc().toIso8601String();
    for (final tabela in <String>[
      'comercios',
      'usuarios',
      'permissoes',
      'configuracoes',
    ]) {
      final dados = await db.query(tabela);
      final estrutura = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
        [tabela],
      );
      await db.insert('backups_logicos', {
        'versao_origem': 4,
        'tabela': tabela,
        'estrutura_sql': estrutura.isEmpty ? null : estrutura.first['sql'],
        'dados_json': jsonEncode(dados),
        'criado_em': agora,
      });
    }
  }
}
