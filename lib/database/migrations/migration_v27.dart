import 'package:sqflite/sqflite.dart';

abstract final class MigrationV27 {
  static const funcoesIniciais = <String>[
    'Manicure',
    'Pedicure',
    'Cabeleireira',
    'Barbeiro',
    'Designer de sobrancelhas',
    'Lash designer',
    'Maquiadora',
    'Esteticista',
    'Massoterapeuta',
    'Depiladora',
    'Tatuadora',
    'Recepcionista',
    'Gerente',
    'Auxiliar',
    'Outra',
  ];

  static Future<void> executar(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS funcoes_profissionais (
      id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL, nome TEXT NOT NULL,
      nome_normalizado TEXT NOT NULL, personalizada INTEGER NOT NULL DEFAULT 0,
      ativo INTEGER NOT NULL DEFAULT 1, criado_em TEXT NOT NULL,
      atualizado_em TEXT NOT NULL, UNIQUE(comercio_id, nome_normalizado)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS profissional_funcoes (
      comercio_id TEXT NOT NULL, profissional_id TEXT NOT NULL, funcao_id TEXT NOT NULL,
      ativo INTEGER NOT NULL DEFAULT 1, atualizado_em TEXT NOT NULL,
      PRIMARY KEY(comercio_id, profissional_id, funcao_id)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS funcao_servicos (
      comercio_id TEXT NOT NULL, funcao_id TEXT NOT NULL, servico_id TEXT NOT NULL,
      ativo INTEGER NOT NULL DEFAULT 1, atualizado_em TEXT NOT NULL,
      PRIMARY KEY(comercio_id, funcao_id, servico_id)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS ia_comandos (
      id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL, unidade_id TEXT,
      usuario_id TEXT NOT NULL, intencao TEXT NOT NULL, modulo TEXT NOT NULL,
      payload_json TEXT NOT NULL, idempotency_key TEXT NOT NULL,
      status TEXT NOT NULL, resultado_json TEXT, erro TEXT,
      criado_em TEXT NOT NULL, confirmado_em TEXT, executado_em TEXT,
      UNIQUE(comercio_id, idempotency_key)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS estoque_lotes_ia (
      id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL, unidade_id TEXT,
      estoque_id TEXT NOT NULL, lote TEXT, quantidade REAL NOT NULL,
      data_fabricacao TEXT, data_validade TEXT, custo REAL, preco_venda REAL,
      fornecedor_id TEXT, codigo_barras TEXT, codigo_interno TEXT,
      observacoes TEXT, ativo INTEGER NOT NULL DEFAULT 1,
      criado_em TEXT NOT NULL, atualizado_em TEXT NOT NULL
    )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_funcoes_profissional ON profissional_funcoes(comercio_id, profissional_id, ativo)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ia_comandos_status ON ia_comandos(comercio_id, status, criado_em)',
    );

    final businesses = await db.query('comercios', columns: ['id']);
    final now = DateTime.now().toUtc().toIso8601String();
    for (final business in businesses) {
      final commerceId = business['id'] as String;
      for (final name in funcoesIniciais) {
        final normalized = _normalize(name);
        await db.insert('funcoes_profissionais', {
          'id': 'func_${commerceId}_$normalized',
          'comercio_id': commerceId,
          'nome': name,
          'nome_normalizado': normalized,
          'personalizada': name == 'Outra' ? 1 : 0,
          'ativo': 1,
          'criado_em': now,
          'atualizado_em': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      final professionals = await db.query(
        'profissionais',
        columns: ['id', 'cargo'],
        where: 'comercio_id = ?',
        whereArgs: [commerceId],
      );
      for (final professional in professionals) {
        final role = (professional['cargo'] as String? ?? '').trim();
        if (role.isEmpty) continue;
        final normalized = _normalize(role);
        final functionId = 'func_${commerceId}_$normalized';
        await db.insert('funcoes_profissionais', {
          'id': functionId,
          'comercio_id': commerceId,
          'nome': role,
          'nome_normalizado': normalized,
          'personalizada': 1,
          'ativo': 1,
          'criado_em': now,
          'atualizado_em': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        await db.insert('profissional_funcoes', {
          'comercio_id': commerceId,
          'profissional_id': professional['id'],
          'funcao_id': functionId,
          'ativo': 1,
          'atualizado_em': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
  }

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}
