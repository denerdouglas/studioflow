import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_schema.dart';
import 'package:studioflow/database/database_schema_latest.dart';

void main() {
  late String dbPath;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dbPath = p.join(
      Directory.systemTemp.path,
      'test_migration_v43_${DateTime.now().millisecondsSinceEpoch}.db',
    );
  });

  tearDownAll(() async {
    final file = File(dbPath);
    if (file.existsSync()) {
      await file.delete();
    }
  });

  test(
    'Upgrade de banco legado preserva registros e adiciona colunas reais na movimentacoes_estoque',
    () async {
      // 1. Criar banco com V41
      Database db = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 41,
          onCreate: (db, version) async {
            // Setup schema real até V41
            await DatabaseSchema.criar(db, 1);
            await DatabaseSchemaLatest.migrar(db, 1, 41);

            // Inserir registro legado antes da V42 e V43
            await db.insert('movimentacoes_estoque', {
              'id': 'legado_1',
              'item_estoque_id': 'item_1',
              'tipo': 'entrada',
              'quantidade': 10,
              'quantidade_anterior': 0,
              'quantidade_posterior': 10,
              'data': '2022-01-01T00:00:00Z',
              'motivo': 'Inicial',
              'comercio_id': 'comercio_teste',
            });
          },
        ),
      );
      await db.close();

      // 2. Fazer Upgrade para Versão Atual (43)
      db = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 43,
          onUpgrade: DatabaseSchemaLatest.migrar,
        ),
      );

      // 3. Pegar informações da tabela
      final columns = await db.rawQuery(
        "PRAGMA table_info('movimentacoes_estoque')",
      );
      final colNames = columns.map((c) => c['name'] as String).toList();

      // 4. Asserts obrigatórios conforme pedido
      expect(colNames, contains('id'));
      expect(colNames, contains('item_estoque_id'));
      expect(colNames, contains('tipo'));
      expect(colNames, contains('quantidade'));
      expect(colNames, contains('quantidade_anterior'));
      expect(colNames, contains('quantidade_posterior'));
      expect(colNames, contains('finalidade'));
      expect(colNames, contains('business_id')); 
      expect(colNames, contains('data'));
      expect(colNames, contains('motivo'));
      expect(colNames, contains('origem'));
      expect(colNames, contains('idempotency_key'));

      // 5. Validar registro legado
      final result = await db.query(
        'movimentacoes_estoque',
        where: 'id = ?',
        whereArgs: ['legado_1'],
      );
      expect(result.length, 1);
      expect(result.first['quantidade'], 10);
      expect(result.first['tipo'], 'entrada');

      await db.close();
    },
  );
}
