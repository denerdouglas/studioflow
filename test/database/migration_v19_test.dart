import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'test_database_factory.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // Creates a database exactly up to Version 18
    db = await TestDatabaseFactory.createAtVersion(18);

    await db.insert('clientes', {
      'id': 'cliente_1',
      'nome': 'João Silva',
      'whatsapp': '11999999999',
      'data_cadastro': '2023-01-01',
    });
  });

  tearDown(() async {
    await db.close();
  });

  test('Deve aplicar migração V19 com sucesso criando as 4 tabelas isoladas por comercio_id', () async {
    // Aplica a migração v19 a partir do banco na V18
    await DatabaseSchemaLatest.migrar(db, 18, 19);

    // Verifica se as novas tabelas foram criadas
    final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
    final tableNames = tables.map((t) => t['name'] as String).toList();

    expect(tableNames, contains('academy_search_history'));
    expect(tableNames, contains('academy_search_cache'));
    expect(tableNames, contains('academy_favorites'));
    expect(tableNames, contains('academy_viewed_courses'));

    // Verifica preservação de dados antigos
    final clientes = await db.query('clientes');
    expect(clientes.length, 1);
    expect(clientes.first['nome'], 'João Silva');

    // Verifica colunas da tabela de histórico
    final historyCols = await db.rawQuery("PRAGMA table_info('academy_search_history')");
    final historyColNames = historyCols.map((c) => c['name'] as String).toList();
    expect(historyColNames, containsAll(['id', 'comercio_id', 'query', 'timestamp']));

    // Verifica colunas da tabela de cache
    final cacheCols = await db.rawQuery("PRAGMA table_info('academy_search_cache')");
    final cacheColNames = cacheCols.map((c) => c['name'] as String).toList();
    expect(cacheColNames, containsAll(['id', 'comercio_id', 'query_normalizada', 'response_json', 'fetched_at', 'expires_at', 'backend_version']));

    // Insere dados para testar índices/unicidade
    await db.insert('academy_search_cache', {
      'id': '1',
      'comercio_id': 'comercio_1',
      'query_normalizada': 'gestao',
      'response_json': '{}',
      'fetched_at': '2023-01-01',
      'expires_at': '2023-01-02',
    });

    // Tentar inserir mesma query e mesmo comercio_id deve falhar ou substituir dependendo do conflito
    try {
      await db.insert('academy_search_cache', {
        'id': '2',
        'comercio_id': 'comercio_1',
        'query_normalizada': 'gestao',
        'response_json': '{}',
        'fetched_at': '2023-01-01',
        'expires_at': '2023-01-02',
      });
      fail('Deveria ter falhado por restrição UNIQUE(comercio_id, query_normalizada)');
    } catch (e) {
      expect(e.toString(), contains('UNIQUE constraint failed'));
    }

    // Inserir mesmo termo para comercio_id diferente deve funcionar
    await db.insert('academy_search_cache', {
      'id': '3',
      'comercio_id': 'comercio_2',
      'query_normalizada': 'gestao',
      'response_json': '{}',
      'fetched_at': '2023-01-01',
      'expires_at': '2023-01-02',
    });
    
    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM academy_search_cache'));
    expect(count, 2);
  });
}
