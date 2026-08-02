import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/migrations/migration_v23.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Migração V23 adiciona as colunas esperadas', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    
    // Criamos o schema v1
    await db.execute('CREATE TABLE servicos (id TEXT PRIMARY KEY)');
    await db.execute('CREATE TABLE servico_materiais (id TEXT PRIMARY KEY)');
    await db.execute('CREATE TABLE pacotes_servicos (id TEXT PRIMARY KEY)');
    await db.execute('CREATE TABLE pacote_vendas (id TEXT PRIMARY KEY)');
    await db.execute('CREATE TABLE agendamentos (id TEXT PRIMARY KEY)');

    // Aplicamos a migração manualmente
    await MigrationV23.executar(db);

    // Verifica se colunas foram adicionadas
    final colsServicos = await db.rawQuery('PRAGMA table_info(servicos)');
    expect(colsServicos.any((c) => c['name'] == 'unidade_id'), isTrue);
    expect(colsServicos.any((c) => c['name'] == 'cor_identificacao'), isTrue);

    final colsServMat = await db.rawQuery('PRAGMA table_info(servico_materiais)');
    expect(colsServMat.any((c) => c['name'] == 'unidade_id'), isTrue);
    expect(colsServMat.any((c) => c['name'] == 'unidade_medida'), isTrue);

    final colsPacotesServ = await db.rawQuery('PRAGMA table_info(pacotes_servicos)');
    expect(colsPacotesServ.any((c) => c['name'] == 'unidade_id'), isTrue);

    final colsPacoteVendas = await db.rawQuery('PRAGMA table_info(pacote_vendas)');
    expect(colsPacoteVendas.any((c) => c['name'] == 'unidade_id'), isTrue);

    final colsAgendamentos = await db.rawQuery('PRAGMA table_info(agendamentos)');
    expect(colsAgendamentos.any((c) => c['name'] == 'unidade_id'), isTrue);

    // Verifica tabelas novas
    final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
    expect(tables.any((t) => t['name'] == 'pdv_vendas'), isTrue);
    expect(tables.any((t) => t['name'] == 'pdv_venda_itens'), isTrue);

    await db.close();
  });
}
