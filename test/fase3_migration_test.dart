import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/core/enums/tipo_produto.dart';
import 'package:studioflow/database/migrations/migration_v29.dart';
import 'package:studioflow/models/domain/ativo_imobilizado.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    // Create base tables needed for the migration
    await db.execute('''
      CREATE TABLE estoque (
        id TEXT PRIMARY KEY,
        comercio_id TEXT,
        business_id TEXT,
        nome TEXT,
        descricao TEXT,
        preco_venda REAL,
        categoria TEXT,
        catalogo_id TEXT,
        estoque_destino TEXT,
        tipo_produto TEXT,
        tipo TEXT,
        tipo_controle TEXT,
        modalidade TEXT,
        unidade TEXT,
        quantidade_atual REAL,
        estoque_minimo REAL,
        ativo INTEGER,
        descontar_automaticamente INTEGER,
        origem_catalogo TEXT,
        data_cadastro TEXT,
        atualizado_em TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE cardapio_itens (
        id TEXT PRIMARY KEY,
        comercio_id TEXT,
        catalogo_id TEXT,
        nome TEXT,
        preco REAL,
        descricao TEXT,
        imagem_url TEXT
      )
    ''');
  });

  tearDown(() async {
    await db.close();
  });

  test('Deve aplicar migration v29 sem erros (ativos_imobilizados)', () async {
    await MigrationV29.executar(db);

    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='ativos_imobilizados'",
    );
    expect(tables.length, 1);
  });

  test('TipoProduto parse de string corretamente', () {
    expect(TipoProduto.fromStorage('venda'), TipoProduto.venda);
    expect(TipoProduto.fromStorage('uso_interno'), TipoProduto.usoInterno);
    expect(TipoProduto.fromStorage('ambos'), TipoProduto.ambos);
    expect(
      TipoProduto.fromStorage('ativo_imobilizado'),
      TipoProduto.ativoImobilizado,
    );

    // Fallback default
    expect(TipoProduto.fromStorage('qualquer_coisa'), TipoProduto.venda);
  });

  test('AtivoImobilizado modelização de dados correta', () {
    final ativo = AtivoImobilizado(
      id: 'atv_1',
      businessId: 'bus_1',
      estoqueId: 'est_1',
      valorAquisicao: 1500.0,
      condicao: 'bom',
    );

    expect(ativo.id, 'atv_1');
    expect(ativo.condicao, 'bom');
    expect(ativo.valorAquisicao, 1500.0);

    final map = ativo.toMap();
    expect(map['business_id'], 'bus_1');
    expect(map['estoque_id'], 'est_1');
    expect(map['condicao'], 'bom');
  });

  test('Migration v29 - Idempotência do Cardápio Legado', () async {
    await db.execute('''
      CREATE TABLE configuracoes (
        chave TEXT PRIMARY KEY,
        valor TEXT,
        comercio_id TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE catalogos_loja (
        id TEXT PRIMARY KEY,
        comercio_id TEXT,
        nome TEXT,
        descricao TEXT,
        tipo_controle TEXT,
        ativo INTEGER,
        ordem INTEGER,
        criado_em TEXT,
        atualizado_em TEXT
      )
    ''');

    await db.insert('cardapio_itens', {
      'id': 'item_1',
      'comercio_id': 'bus_1',
      'nome': 'Bolo',
      'preco': 10.0,
    });

    // Primeira execução
    await MigrationV29.executar(db);

    final allCatalogos = await db.query('catalogos_loja');
    print('Catalogos: $allCatalogos');

    final allConfig = await db.query('configuracoes');
    print('Configuracoes: $allConfig');

    final catalogos = await db.query(
      'catalogos_loja',
      where: "comercio_id = 'bus_1'",
    );
    expect(catalogos.length, 1);
    expect(catalogos.first['nome'], 'Cardápio Legado');

    final config = await db.query(
      'configuracoes',
      where: "chave = 'cardapio_migrado_bus_1'",
    );
    expect(config.length, 1);

    final itens = await db.query('estoque', where: "comercio_id = 'bus_1'");
    expect(itens.length, 1);
    expect(itens.first['nome'], 'Bolo');

    // Segunda execução - não deve duplicar o catálogo
    await MigrationV29.executar(db);
    final catalogos2 = await db.query(
      'catalogos_loja',
      where: "comercio_id = 'bus_1'",
    );
    expect(catalogos2.length, 1); // Continua 1
  });
}
