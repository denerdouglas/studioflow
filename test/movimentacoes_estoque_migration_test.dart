import 'package:path/path.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/core/constants/database_constants.dart';
import 'package:studioflow/database/database_service.dart';
import 'package:studioflow/database/database_schema_latest.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await DatabaseService.instance.fecharBanco();
  });

  test(
    'Migration V42 garante que movimentacoes_estoque tenha todas as colunas',
    () async {
      final dbPath = await databaseFactory.getDatabasesPath();
      final path = join(dbPath, 'test_mov_estoque.db');
      await databaseFactory.deleteDatabase(path);

      // 1. Criar banco com V41 (legado sem finalidade)
      var db = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 41,
          onCreate: (db, version) async {
            await db.execute('''
            CREATE TABLE movimentacoes_estoque (
              id TEXT PRIMARY KEY,
              item_estoque_id TEXT NOT NULL,
              tipo TEXT NOT NULL,
              quantidade REAL NOT NULL,
              quantidade_anterior REAL NOT NULL,
              quantidade_posterior REAL NOT NULL,
              data TEXT NOT NULL,
              motivo TEXT NOT NULL,
              usuario_responsavel_id TEXT
            )
          ''');

            await db.insert('movimentacoes_estoque', {
              'id': 'legado_1',
              'item_estoque_id': 'prod_a',
              'tipo': 'entrada',
              'quantidade': 10,
              'quantidade_anterior': 0,
              'quantidade_posterior': 10,
              'data': '2020-01-01T00:00:00.000Z',
              'motivo': 'migracao_teste',
            });
          },
        ),
      );
      await db.close();

      // 2. Executar upgrade usando a lÃ³gica de produÃ§Ã£o real
      db = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: DatabaseConstants.versao,
          onUpgrade: DatabaseSchemaLatest.migrar,
        ),
      );

      // 3. Inspecionar as colunas da tabela pÃ³s-upgrade
      final List<Map<String, Object?>> columns = await db.rawQuery(
        "PRAGMA table_info('movimentacoes_estoque')",
      );
      final colNames = columns.map((c) => c['name'] as String).toList();

      expect(colNames, contains('id'));
      expect(colNames, contains('comercio_id'));
      expect(colNames, contains('item_estoque_id'));
      expect(colNames, contains('tipo'));
      expect(colNames, contains('quantidade'));
      expect(colNames, contains('quantidade_anterior'));
      expect(colNames, contains('quantidade_posterior'));
      expect(colNames, contains('finalidade'));
      expect(colNames, contains('data'));
      expect(colNames, contains('motivo'));
      expect(colNames, contains('usuario_responsavel_id'));
      expect(colNames, contains('origem'));
      expect(colNames, contains('referencia_id'));
      expect(colNames, contains('justificativa_negativo'));
      expect(colNames, contains('idempotency_key'));
      expect(colNames, contains('business_id'));

      // 4. Garantir preservaÃ§Ã£o de dados
      final rows = await db.query(
        'movimentacoes_estoque',
        where: "id = 'legado_1'",
      );
      expect(rows.length, 1);
      expect(rows.first['motivo'], 'migracao_teste');

      await db.close();
    },
  );
}
