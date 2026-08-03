import 'package:sqflite/sqflite.dart';

class MigrationV23 {
  static Future<void> executar(Database db) async {
    // 1. Adicionar unidade_id e cor_identificacao em servicos
    await _addColumn(db, 'servicos', 'unidade_id', 'TEXT');
    await _addColumn(db, 'servicos', 'cor_identificacao', 'TEXT');

    // 2. Adicionar unidade_id e unidade_medida em servico_materiais
    await _addColumn(db, 'servico_materiais', 'unidade_id', 'TEXT');
    await _addColumn(db, 'servico_materiais', 'unidade_medida', 'TEXT');

    // 3. Adicionar unidade_id em pacotes_servicos
    await _addColumn(db, 'pacotes_servicos', 'unidade_id', 'TEXT');

    // 4. Adicionar unidade_id em pacote_vendas
    await _addColumn(db, 'pacote_vendas', 'unidade_id', 'TEXT');

    // 5. Garantir que agendamentos tenha unidade_id (pode ter sido adicionado antes, mas garantimos aqui)
    await _addColumn(db, 'agendamentos', 'unidade_id', 'TEXT');

    // 6. Criar tabela loja / pdv_vendas simplificada se não houver algo parecido para colaborador
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pdv_vendas (
        id TEXT PRIMARY KEY,
        comercio_id TEXT NOT NULL,
        unidade_id TEXT,
        profissional_id TEXT NOT NULL,
        cliente_id TEXT,
        valor_total REAL NOT NULL,
        data_venda TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'concluida'
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pdv_venda_itens (
        id TEXT PRIMARY KEY,
        pdv_venda_id TEXT NOT NULL,
        produto_id TEXT NOT NULL,
        quantidade REAL NOT NULL,
        valor_unitario REAL NOT NULL,
        FOREIGN KEY (pdv_venda_id) REFERENCES pdv_vendas(id) ON DELETE CASCADE
      )
    ''');
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
      // Tabela pode não existir, ignorar
    }
  }
}
