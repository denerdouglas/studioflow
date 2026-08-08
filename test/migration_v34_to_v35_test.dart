import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/migrations/migration_v35.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
  });

  tearDown(() async {
    if (db.isOpen) {
      await db.close();
    }
  });

  test('Migration V34 to V35 - Deve adicionar colunas legadas no estoque sem perder dados', () async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 34,
        onCreate: (db, version) async {
          // Simulando o estado na versão 34
          await db.execute('''
            CREATE TABLE comercios (
              id TEXT PRIMARY KEY,
              nome TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE estoque (
              id TEXT PRIMARY KEY,
              comercio_id TEXT,
              business_id TEXT,
              produto_id TEXT NOT NULL,
              quantidade REAL NOT NULL,
              atualizado_em TEXT NOT NULL
            )
          ''');
          
          await db.insert('estoque', {
            'id': 'est_1',
            'comercio_id': 'com_1',
            'produto_id': 'prod_1',
            'quantidade': 10.0,
            'atualizado_em': DateTime.now().toIso8601String(),
          });

          await db.insert('estoque', {
            'id': 'est_2',
            'business_id': 'bus_2',
            'produto_id': 'prod_2',
            'quantidade': 5.0,
            'atualizado_em': DateTime.now().toIso8601String(),
          });
        },
      ),
    );



    // Executa a migration diretamente para o teste
    await MigrationV35.executar(db);

    // Verifica se os dados foram mantidos e atualizados
    final rows = await db.query('estoque', orderBy: 'id');
    expect(rows.length, 2);
    
    // est_1
    expect(rows[0]['id'], 'est_1');
    expect(rows[0]['comercio_id'], 'com_1');
    expect(rows[0]['quantidade'], 10.0);

    // est_2 - backfill de comercio_id a partir de business_id
    expect(rows[1]['id'], 'est_2');
    expect(rows[1]['comercio_id'], 'bus_2');
    expect(rows[1]['quantidade'], 5.0);

    // Verifica se a tabela sqlite_master reporta as colunas novas da migration V35
    final tableInfo = await db.rawQuery("PRAGMA table_info(estoque)");
    final columns = tableInfo.map((row) => row['name'] as String).toList();

    expect(columns, contains('tipo_produto'));
    expect(columns, contains('estoque_destino'));
    expect(columns, contains('modalidade'));
    expect(columns, contains('codigo_barras'));
    expect(columns, contains('ativo'));
    expect(columns, contains('quantidade_atual'));
    expect(columns, contains('estoque_minimo'));

    // Verifica se os defaults foram aplicados corretamente
    expect(rows[0]['tipo_produto'], 'ambos');
    expect(rows[0]['estoque_destino'], 'salao');
    expect(rows[0]['ativo'], 1);
  });
}
