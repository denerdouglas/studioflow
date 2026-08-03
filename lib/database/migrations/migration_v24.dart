import 'package:sqflite/sqflite.dart';

class MigrationV24 {
  static Future<void> executar(Database db) async {
    // 1. Tabela para rastreamento de peças únicas (Joias/Consignados Individuais)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pecas_unicas (
        id TEXT PRIMARY KEY,
        comercio_id TEXT NOT NULL,
        codigo_exclusivo TEXT NOT NULL,
        nome TEXT NOT NULL,
        descricao TEXT,
        material TEXT,
        marca TEXT,
        fornecedor_id TEXT,
        custo REAL NOT NULL DEFAULT 0,
        preco REAL NOT NULL,
        lote_id TEXT,
        unidade_id TEXT,
        localizacao TEXT,
        cliente_id TEXT,
        profissional_vendedor_id TEXT,
        comissao REAL,
        data_venda TEXT,
        status TEXT NOT NULL DEFAULT 'disponivel',
        data_cadastro TEXT NOT NULL,
        UNIQUE(comercio_id, codigo_exclusivo)
      )
    ''');

    // 2. Tabela para rastreamento de transferências de estoque entre unidades
    await db.execute('''
      CREATE TABLE IF NOT EXISTS transferencias_estoque (
        id TEXT PRIMARY KEY,
        comercio_id TEXT NOT NULL,
        unidade_origem_id TEXT NOT NULL,
        unidade_destino_id TEXT NOT NULL,
        usuario_responsavel_id TEXT NOT NULL,
        data_transferencia TEXT NOT NULL,
        motivo TEXT,
        status TEXT NOT NULL DEFAULT 'concluida'
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS transferencias_estoque_itens (
        id TEXT PRIMARY KEY,
        transferencia_id TEXT NOT NULL,
        item_estoque_id TEXT,
        peca_unica_id TEXT,
        quantidade REAL NOT NULL,
        FOREIGN KEY (transferencia_id) REFERENCES transferencias_estoque(id) ON DELETE CASCADE
      )
    ''');

    // 3. Atualizar estoque para suportar lote, validade, e alerta de vencimento (bebidas/alimentos)
    await _addColumn(db, 'estoque', 'lote', 'TEXT');
    await _addColumn(db, 'estoque', 'data_fabricacao', 'TEXT');
    await _addColumn(
      db,
      'estoque',
      'alerta_vencimento_dias',
      'INTEGER DEFAULT 0',
    );
  }

  static Future<void> _addColumn(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    try {
      final columns = await db.rawQuery('PRAGMA table_info($table)');
      if (!columns.any((item) => item['name'] == column)) {
        await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
      }
    } catch (e) {
      // Ignorar se a tabela não existir
    }
  }
}
