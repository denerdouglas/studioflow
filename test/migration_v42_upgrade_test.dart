import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/migrations/migration_v42.dart';
import 'package:studioflow/database/database_schema_verifier.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'Upgrade V41 -> V42 adiciona finalidade em movimentacoes_estoque e preserva dados',
    () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);

      // Simular schema antigo SEM finalidade e colunas novas
      await db.execute('''
      CREATE TABLE movimentacoes_estoque (
        id TEXT PRIMARY KEY,
        item_estoque_id TEXT NOT NULL,
        tipo TEXT NOT NULL,
        quantidade REAL NOT NULL,
        quantidade_anterior REAL NOT NULL,
        quantidade_posterior REAL NOT NULL,
        data TEXT NOT NULL,
        motivo TEXT
      )
    ''');

      await db.insert('movimentacoes_estoque', {
        'id': 'mov_1',
        'item_estoque_id': 'est_1',
        'tipo': 'entrada',
        'quantidade': 10,
        'quantidade_anterior': 0,
        'quantidade_posterior': 10,
        'data': '2023-01-01T10:00:00.000Z',
        'motivo': 'Saldo inicial',
      });

      // Validar se tabela foi criada com 8 colunas e sem finalidade
      var cols = await db.rawQuery('PRAGMA table_info(movimentacoes_estoque)');
      expect(cols.any((c) => c['name'] == 'finalidade'), isFalse);
      expect(cols.any((c) => c['name'] == 'origem'), isFalse);

      // Executar migração V42
      await MigrationV42.executar(db);

      // Validar schema de V42
      cols = await db.rawQuery('PRAGMA table_info(movimentacoes_estoque)');
      expect(cols.any((c) => c['name'] == 'finalidade'), isTrue);
      expect(cols.any((c) => c['name'] == 'origem'), isTrue);
      expect(cols.any((c) => c['name'] == 'referencia_id'), isTrue);
      expect(cols.any((c) => c['name'] == 'justificativa_negativo'), isTrue);
      expect(cols.any((c) => c['name'] == 'business_id'), isTrue);
      expect(cols.any((c) => c['name'] == 'comercio_id'), isTrue);
      expect(cols.any((c) => c['name'] == 'idempotency_key'), isTrue);

      // Validar preservação de dados
      final dados = await db.query('movimentacoes_estoque');
      expect(dados.length, 1);
      expect(dados.first['id'], 'mov_1');
      expect(dados.first['tipo'], 'entrada');
      expect(dados.first['finalidade'], null);

      await db.close();
    },
  );

  test(
    'DatabaseSchemaVerifier adiciona colunas de movimentacoes_estoque',
    () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);

      await db.execute('''
      CREATE TABLE movimentacoes_estoque (
        id TEXT PRIMARY KEY,
        item_estoque_id TEXT NOT NULL,
        tipo TEXT NOT NULL,
        quantidade REAL NOT NULL,
        quantidade_anterior REAL NOT NULL,
        quantidade_posterior REAL NOT NULL,
        data TEXT NOT NULL,
        motivo TEXT
      )
    ''');

      await db.execute('CREATE TABLE estoque (id TEXT PRIMARY KEY)');
      await db.execute('CREATE TABLE agendamentos (id TEXT PRIMARY KEY)');

      await DatabaseSchemaVerifier.repair(db);

      var cols = await db.rawQuery('PRAGMA table_info(movimentacoes_estoque)');
      expect(cols.any((c) => c['name'] == 'finalidade'), isTrue);

      await db.close();
    },
  );
}
