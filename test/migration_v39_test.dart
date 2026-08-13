import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/migrations/migration_v39.dart';
import 'package:studioflow/database/database_schema_latest.dart';

void main() {
  sqfliteFfiInit();

  test('V39 preserva registros e faz backfill somente estrutural', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('''CREATE TABLE movimentacoes_financeiras (
      id TEXT PRIMARY KEY, comercio_id TEXT, tipo TEXT, descricao TEXT,
      valor REAL, status TEXT, data TEXT, agendamento_id TEXT, servico_id TEXT,
      observacoes TEXT)''');
    await db.execute('''CREATE TABLE pdv_vendas (
      id TEXT PRIMARY KEY, comercio_id TEXT)''');
    await db.execute('''CREATE TABLE pacotes_vendidos (
      id TEXT PRIMARY KEY, business_id TEXT)''');
    await db.insert('pdv_vendas', {'id': 'sale', 'comercio_id': 'c1'});
    await db.insert('pacotes_vendidos', {'id': 'pack', 'business_id': 'c1'});
    await db.insert('movimentacoes_financeiras', {
      'id': 'service',
      'comercio_id': 'c1',
      'agendamento_id': 'a1',
    });
    await db.insert('movimentacoes_financeiras', {
      'id': 'sale_p0',
      'comercio_id': 'c1',
    });
    await db.insert('movimentacoes_financeiras', {
      'id': 'package',
      'comercio_id': 'c1',
      'observacoes': 'pacote_venda_id=pack',
    });
    await db.insert('movimentacoes_financeiras', {
      'id': 'ambiguous',
      'comercio_id': 'c1',
      'descricao': 'Venda de produto',
    });

    await MigrationV39.executar(db);
    await MigrationV39.executar(db);

    final rows = await db.query('movimentacoes_financeiras', orderBy: 'id');
    expect(rows, hasLength(4));
    String? center(String id) =>
        rows.firstWhere((row) => row['id'] == id)['centro_resultado']
            as String?;
    expect(center('service'), 'salao');
    expect(center('sale_p0'), 'loja');
    expect(center('package'), 'salao');
    expect(center('ambiguous'), isNull);
  });

  test('banco novo já nasce com classificação financeira', () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 39,
        onCreate: DatabaseSchemaLatest.criar,
      ),
    );
    addTearDown(db.close);
    final columns = await db.rawQuery(
      'PRAGMA table_info(movimentacoes_financeiras)',
    );
    final names = columns.map((row) => row['name']).toSet();
    expect(
      names,
      containsAll(<String>{
        'centro_resultado',
        'entidade_origem',
        'entidade_origem_id',
      }),
    );
  });
}
