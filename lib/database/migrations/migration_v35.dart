import 'package:sqflite/sqflite.dart';

abstract final class MigrationV35 {
  static Future<void> executar(Database db) async {
    final colunas = await db.rawQuery('PRAGMA table_info(estoque)');
    final nomesColunas = colunas.map((c) => c['name'].toString().toLowerCase()).toSet();

    Future<void> add(String nome, String definicao) async {
      if (!nomesColunas.contains(nome.toLowerCase())) {
        await db.execute('ALTER TABLE estoque ADD COLUMN $nome $definicao');
      }
    }

    // Colunas ausentes que as queries atuais ainda referenciam
    await add('comercio_id', 'TEXT');
    await add('estoque_destino', "TEXT DEFAULT 'salao'");
    await add('tipo_produto', "TEXT DEFAULT 'ambos'");
    await add('catalogo_id', 'TEXT');
    await add('codigo_interno', 'TEXT');
    await add('preco_venda', 'REAL DEFAULT 0');
    await add('modalidade', 'TEXT');
    await add('lote', 'TEXT');
    await add('unidade_id', 'TEXT');
    await add('quantidade', 'REAL DEFAULT 0'); // Usado em algumas queries legadas
    await add('codigo_barras', 'TEXT');
    await add('ativo', 'INTEGER DEFAULT 1');
    await add('quantidade_atual', 'REAL DEFAULT 0');
    await add('estoque_minimo', 'REAL DEFAULT 0');

    if (nomesColunas.contains('business_id')) {
      await db.execute('''
        UPDATE estoque 
        SET comercio_id = business_id 
        WHERE (comercio_id IS NULL OR comercio_id = '') 
          AND business_id IS NOT NULL 
          AND business_id != ''
      ''');
    }
  }
}
