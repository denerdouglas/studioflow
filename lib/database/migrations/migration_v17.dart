import 'package:sqflite/sqflite.dart';

abstract final class MigrationV17 {
  static Future<void> executar(Database db) async {
    // 1. Tabela fotos_cliente
    await db.execute('''
      CREATE TABLE IF NOT EXISTS fotos_cliente (
        id TEXT PRIMARY KEY,
        comercio_id TEXT NOT NULL,
        cliente_id TEXT NOT NULL,
        file_path_local TEXT NOT NULL,
        remote_url TEXT,
        thumbnail_path TEXT NOT NULL,
        servico_id TEXT,
        agendamento_id TEXT,
        profissional_id TEXT,
        atendimento_id TEXT,
        venda_id TEXT,
        descricao TEXT,
        categoria TEXT NOT NULL,
        data_trabalho TEXT NOT NULL,
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL,
        status_sincronizacao INTEGER NOT NULL DEFAULT 0,
        excluido_em TEXT
      )
    ''');

    // 2. Tabela catalogo_importacoes_temporarias
    await db.execute('''
      CREATE TABLE IF NOT EXISTS catalogo_importacoes_temporarias (
        id TEXT PRIMARY KEY,
        comercio_id TEXT NOT NULL,
        status TEXT NOT NULL,
        arquivo_path TEXT NOT NULL,
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL
      )
    ''');

    // 3. Tabela catalogo_itens_temporarios
    await db.execute('''
      CREATE TABLE IF NOT EXISTS catalogo_itens_temporarios (
        id TEXT PRIMARY KEY,
        importacao_id TEXT NOT NULL,
        comercio_id TEXT NOT NULL,
        status_item TEXT NOT NULL,
        codigo TEXT,
        nome TEXT,
        descricao TEXT,
        categoria TEXT,
        fornecedor TEXT,
        preco_custo REAL,
        preco_venda REAL,
        quantidade REAL,
        comissao REAL,
        prazo_devolucao TEXT,
        status_consignado TEXT,
        imagem_path TEXT,
        observacoes TEXT,
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL,
        FOREIGN KEY (importacao_id) REFERENCES catalogo_importacoes_temporarias (id) ON DELETE CASCADE
      )
    ''');

    // 4. Novas colunas em clientes
    await _adicionarColuna(db, 'clientes', 'instagram_url', 'TEXT');
    await _adicionarColuna(db, 'clientes', 'tiktok_url', 'TEXT');
    await _adicionarColuna(db, 'clientes', 'facebook_url', 'TEXT');
    await _adicionarColuna(db, 'clientes', 'website_url', 'TEXT');
    await _adicionarColuna(db, 'clientes', 'avatar_path_local', 'TEXT');
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
