import 'package:sqflite/sqflite.dart';

abstract final class MigrationV28 {
  static const sugestoes = <String>[
    'Salão de beleza',
    'Manicure e pedicure',
    'Barbearia',
    'Sobrancelhas',
    'Cílios',
    'Massagem',
    'Estética',
  ];

  static Future<void> executar(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS modalidades_estabelecimento (
      id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL, nome TEXT NOT NULL,
      nome_normalizado TEXT NOT NULL, descricao TEXT, icone TEXT,
      imagem_capa TEXT, cor TEXT, ordem INTEGER NOT NULL DEFAULT 0,
      favorita INTEGER NOT NULL DEFAULT 0, exibir_home INTEGER NOT NULL DEFAULT 1,
      ativa INTEGER NOT NULL DEFAULT 1, personalizada INTEGER NOT NULL DEFAULT 0,
      criado_em TEXT NOT NULL, atualizado_em TEXT NOT NULL,
      UNIQUE(comercio_id, nome_normalizado)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS modalidade_servicos (
      comercio_id TEXT NOT NULL, modalidade_id TEXT NOT NULL,
      servico_id TEXT NOT NULL, ativo INTEGER NOT NULL DEFAULT 1,
      atualizado_em TEXT NOT NULL,
      PRIMARY KEY(comercio_id, modalidade_id, servico_id)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS modalidade_profissionais (
      comercio_id TEXT NOT NULL, modalidade_id TEXT NOT NULL,
      profissional_id TEXT NOT NULL, ativo INTEGER NOT NULL DEFAULT 1,
      atualizado_em TEXT NOT NULL,
      PRIMARY KEY(comercio_id, modalidade_id, profissional_id)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS modalidade_funcoes (
      comercio_id TEXT NOT NULL, modalidade_id TEXT NOT NULL,
      funcao_id TEXT NOT NULL, ativo INTEGER NOT NULL DEFAULT 1,
      atualizado_em TEXT NOT NULL,
      PRIMARY KEY(comercio_id, modalidade_id, funcao_id)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS modalidade_estoque (
      comercio_id TEXT NOT NULL, modalidade_id TEXT NOT NULL,
      estoque_id TEXT NOT NULL, ativo INTEGER NOT NULL DEFAULT 1,
      atualizado_em TEXT NOT NULL,
      PRIMARY KEY(comercio_id, modalidade_id, estoque_id)
    )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_modalidades_ordem ON modalidades_estabelecimento(comercio_id, ativa, ordem)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_modalidade_servicos ON modalidade_servicos(comercio_id, servico_id, ativo)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_modalidade_profissionais ON modalidade_profissionais(comercio_id, profissional_id, ativo)',
    );

    final now = DateTime.now().toUtc().toIso8601String();
    final businesses = await db.query('comercios', columns: ['id']);
    for (final business in businesses) {
      final commerceId = business['id'] as String;
      final existing = await db.query(
        'modalidades_estabelecimento',
        where: 'comercio_id=?',
        whereArgs: [commerceId],
        limit: 1,
      );
      if (existing.isNotEmpty) continue;
      await db.insert('modalidades_estabelecimento', {
        'id': 'modalidade_${commerceId}_salao',
        'comercio_id': commerceId,
        'nome': sugestoes.first,
        'nome_normalizado': 'salao_de_beleza',
        'descricao': 'Modalidade inicial preservada na migração.',
        'icone': 'content_cut',
        'cor': '#8E5CE6',
        'ordem': 0,
        'favorita': 1,
        'exibir_home': 1,
        'ativa': 1,
        'personalizada': 0,
        'criado_em': now,
        'atualizado_em': now,
      });
    }
  }
}
