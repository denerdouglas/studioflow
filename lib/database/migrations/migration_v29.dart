import 'package:sqflite/sqflite.dart';
import '../../core/utils/id_generator.dart';


abstract final class MigrationV29 {
  static Future<void> executar(Database db) async {
    // 1. Criar tabela ativos_imobilizados (Extensão 1:1 de estoque)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ativos_imobilizados (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        estoque_id TEXT NOT NULL,
        data_aquisicao TEXT,
        valor_aquisicao REAL DEFAULT 0 CHECK (valor_aquisicao >= 0),
        numero_serie TEXT,
        patrimonio TEXT,
        localizacao TEXT,
        condicao TEXT,
        garantia_ate TEXT,
        observacoes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        created_by TEXT,
        updated_by TEXT,
        FOREIGN KEY (estoque_id) REFERENCES estoque (id) ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_ativos_imob_estoque_uniq 
      ON ativos_imobilizados (business_id, estoque_id) 
      WHERE deleted_at IS NULL
    ''');
    
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_ativos_imob_business 
      ON ativos_imobilizados (business_id)
    ''');

    // 2. Adaptação Idempotente Cardápio -> Catálogo / Estoque
    final comerciosRows = await db.rawQuery('SELECT DISTINCT comercio_id FROM cardapio_itens');
    final agora = DateTime.now().toUtc().toIso8601String();
    
    for (var comercio in comerciosRows) {
      final businessId = comercio['comercio_id'] as String;
      final flagChave = 'cardapio_migrado_$businessId';
      
      final flagRow = await db.query(
        'configuracoes',
        where: 'chave = ?',
        whereArgs: [flagChave],
      );
      
      if (flagRow.isEmpty) {
        final itens = await db.query(
          'cardapio_itens',
          where: 'comercio_id = ?',
          whereArgs: [businessId],
        );
        
        if (itens.isNotEmpty) {
          // Criar catálogo legado para abrigar esses itens sem perder associação
          final catalogoId = 'cat_${IdGenerator.temporal()}';
          await db.insert('catalogos_loja', {
            'id': catalogoId,
            'comercio_id': businessId,
            'nome': 'Cardápio Legado',
            'descricao': 'Catálogo importado automaticamente do cardápio antigo',
            'tipo_controle': 'item_individual',
            'ativo': 1,
            'ordem': 99,
            'criado_em': agora,
            'atualizado_em': agora,
          });
          
          for (var item in itens) {
            final id = item['id'] as String;
            final nome = item['nome'] as String;
            final descricao = item['descricao'] as String?;
            final preco = (item['preco'] as num?)?.toDouble() ?? 0.0;
            final categoria = item['categoria'] as String? ?? 'Outros';
            final ativo = item['ativo'] as int? ?? 1;
            
            // Preservar a identidade do registro original.
            final exists = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM estoque WHERE id = ?', [id])) ?? 0;
            
            if (exists == 0) {
              await db.insert('estoque', {
                'id': id,
                'business_id': businessId,
                'comercio_id': businessId,
                'nome': nome,
                'descricao': descricao,
                'preco_venda': preco,
                'categoria': categoria,
                'catalogo_id': catalogoId,
                'estoque_destino': 'loja',
                'tipo_produto': 'venda',
                'tipo': 'item_individual',
                'tipo_controle': 'item_individual',
                'modalidade': 'proprio',
                'unidade': 'un',
                'quantidade_atual': 0,
                'estoque_minimo': 0,
                'ativo': ativo,
                'descontar_automaticamente': 1,
                'origem_catalogo': 'migracao_cardapio',
                'data_cadastro': agora,
                'atualizado_em': agora,
                'created_at': agora,
                'updated_at': agora,
              });
            }
          }
        }
        
        // Registrar conclusão de forma estrita e transacional (por empresa)
        await db.insert('configuracoes', {
          'chave': flagChave,
          'valor': 'true',
        });
      }
    }
  }
}
