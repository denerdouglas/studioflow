import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/models/domain/acesso.dart';
import 'package:studioflow/repositories/commercial_repository.dart';
import 'package:studioflow/database/database_schema_latest.dart';

void main() {
  late Database db;
  late CommercialRepository repository;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: DatabaseSchemaLatest.criar,
      ),
    );
    repository = CommercialRepository(databaseProvider: () async => db);
  });

  tearDown(() async {
    if (db.isOpen) {
      await db.close();
    }
  });

  test('CommercialRepository pode ser instanciado sem erros', () async {
    expect(repository, isNotNull);
  });
}
