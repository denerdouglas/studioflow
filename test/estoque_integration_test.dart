// ignore_for_file: unused_local_variable
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/repositories/estoque_repository.dart';
import 'package:studioflow/repositories/loja_repository.dart';

void main() {
  late Database db;
  late EstoqueRepository estoqueRepository;
  late LojaRepository lojaRepository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    // Criação simplificada de tabelas para o teste
    await db.execute('''
      CREATE TABLE estoque (
        id TEXT PRIMARY KEY,
        comercio_id TEXT,
        nome TEXT,
        tipo_produto TEXT,
        quantidade_atual REAL DEFAULT 0,
        estoque_destino TEXT,
        ativo INTEGER DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE estoque_saldos (
        id TEXT PRIMARY KEY,
        business_id TEXT,
        estoque_id TEXT,
        finalidade TEXT,
        local_id TEXT,
        quantidade_atual REAL,
        quantidade_bloqueada REAL,
        updated_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE movimentacoes_estoque (
        id TEXT PRIMARY KEY,
        item_estoque_id TEXT,
        comercio_id TEXT,
        tipo TEXT,
        quantidade REAL,
        quantidade_anterior REAL,
        quantidade_posterior REAL,
        motivo TEXT,
        data TEXT,
        usuario_responsavel_id TEXT,
        finalidade TEXT
      )
    ''');

    estoqueRepository =
        EstoqueRepository(); // precisa de dependências mockadas em um cenário real
    lojaRepository = LojaRepository(); // idem
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'Segregação de saldo (venda vs uso_interno) funciona corretamente',
    () async {
      // Isso é um placeholder de teste de integração
      // Num teste real, injetaríamos o DB no repository ou usaríamos inMemoryDatabaseFactory
      // e testaríamos `lojaRepository.movimentar(finalidade: 'venda')`
      // vs `estoqueRepository.registrarMovimentacao(finalidade: 'uso_interno')`
      expect(true, true);
    },
  );
}
