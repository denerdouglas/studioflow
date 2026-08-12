import 'package:path/path.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/core/constants/database_constants.dart';
import 'package:studioflow/database/database_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await DatabaseService.instance.fecharBanco();
  });

  Future<Database> criarBancoLegadoV30() async {
    final dbPath = await databaseFactory.getDatabasesPath();
    // Usa path.join para garantir mesma string no Windows/Linux igual ao DatabaseService
    final path = join(dbPath, DatabaseConstants.nomeArquivo);
    // Limpar antes
    await databaseFactory.deleteDatabase(path);

    // Cria banco com esquema de "versão 30", que NÃO tem business_id em estoque.
    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 30, // Forçando a versão 30
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE estoque (
              id TEXT PRIMARY KEY,
              nome TEXT NOT NULL,
              categoria TEXT NOT NULL,
              tipo TEXT NOT NULL,
              quantidade_atual REAL NOT NULL DEFAULT 0,
              comercio_id TEXT
            )
          ''');

          await db.execute('''
            CREATE TABLE clientes (
              id TEXT PRIMARY KEY,
              nome TEXT NOT NULL,
              whatsapp TEXT NOT NULL
            )
          ''');

          await db.insert('estoque', {
            'id': 'est_1',
            'nome': 'Shampoo',
            'categoria': 'Cosmeticos',
            'tipo': 'Produto',
            'quantidade_atual': 10,
            'comercio_id': 'comercio_legacy_1',
          });

          await db.insert('clientes', {
            'id': 'cli_1',
            'nome': 'João',
            'whatsapp': '11999999999',
          });
        },
      ),
    );
    await db.close();
    return databaseFactory.openDatabase(path);
  }

  Future<Database> criarBancoLegadoV36Quebrado() async {
    final dbPath = await databaseFactory.getDatabasesPath();
    final path = join(dbPath, DatabaseConstants.nomeArquivo);
    await databaseFactory.deleteDatabase(path);

    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 36, // Atenção: o banco JÁ É v36 ou superior
        onCreate: (db, version) async {
          // Mas foi criado com um schema quebrado (sem business_id) porque a migration não rodou
          await db.execute('''
            CREATE TABLE estoque (
              id TEXT PRIMARY KEY,
              nome TEXT NOT NULL,
              categoria TEXT NOT NULL,
              tipo TEXT NOT NULL,
              quantidade_atual REAL NOT NULL DEFAULT 0,
              comercio_id TEXT
            )
          ''');
          await db.insert('estoque', {
            'id': 'est_2',
            'nome': 'Condicionador',
            'categoria': 'Cosmeticos',
            'tipo': 'Produto',
            'quantidade_atual': 5,
            'comercio_id': 'comercio_legacy_2',
          });
        },
      ),
    );
    await db.close();
    return databaseFactory.openDatabase(
      path,
    ); // Apenas abre para termos a referência se precisar, mas DatabaseService cuidará
  }

  test(
    'Cenário A: Banco antigo v30 -> Upgrade normal -> Repair Funciona',
    () async {
      // Prepara banco legado na v30
      await criarBancoLegadoV30();

      // Inicia o app usando o DatabaseService oficial
      final db = await DatabaseService.instance.database;

      // Garante que o verifier adicionou business_id na tabela estoque
      final colunas = await db.rawQuery('PRAGMA table_info(estoque)');
      expect(colunas.any((c) => c['name'] == 'business_id'), true);

      // Garante backfill
      final itens = await db.query('estoque');

      final row = itens.firstWhere((r) => r['id'] == 'est_1');
      expect(row['business_id'], 'comercio_legacy_1');
      expect(row['nome'], 'Shampoo'); // Preservou dado

      // Garante preservação de outras tabelas
      final clientes = await db.query('clientes');
      expect(clientes.length, 1);
      expect(clientes.first['nome'], 'João');
    },
  );

  test(
    'Cenário B e E: Banco já v36+ (sem business_id) -> Repair Funciona e Permite Insert',
    () async {
      // Prepara banco que já tem versão alta mas está sem a coluna (erro clássico)
      await criarBancoLegadoV36Quebrado();

      // Abrimos pelo DatabaseService (vai ignorar o onUpgrade normal do Sqflite,
      // mas o SchemaVerifier vai rodar logo depois!)
      final db = await DatabaseService.instance.database;

      final colunas = await db.rawQuery('PRAGMA table_info(estoque)');
      expect(colunas.any((c) => c['name'] == 'business_id'), true);

      // Garante backfill
      final itens = await db.query('estoque', where: "id = 'est_2'");
      expect(itens.first['business_id'], 'comercio_legacy_2');

      // Cenário E: Tentar fazer o Insert moderno que estava quebrando
      await db.insert('estoque', {
        'id': 'est_novo',
        'business_id': 'novo_business',
        'nome': 'Novo Produto',
        'categoria': 'Cat',
        'tipo': 'Tipo',
        'quantidade_atual': 1,
      });

      final novo = await db.query('estoque', where: "id = 'est_novo'");
      expect(novo.isNotEmpty, true);
      expect(novo.first['business_id'], 'novo_business');
    },
  );

  test(
    'Cenário C e D: Banco Novo ou Já Reparado -> Zero erro, Zero duplicação',
    () async {
      // Abre um banco zerado
      await DatabaseService.instance.database;

      // Fechamos
      await DatabaseService.instance.fecharBanco();

      // Reabrimos (Cenário C)
      final dbReaberto = await DatabaseService.instance.database;
      final colunas = await dbReaberto.rawQuery('PRAGMA table_info(estoque)');

      // Assegura que só existe 1 business_id (o sqflite nem permitiria 2, mas garante que n crashou)
      final bizCols = colunas.where((c) => c['name'] == 'business_id');
      expect(bizCols.length, 1);

      // Testa também que tabelas adicionais estão ok
      final tables = await dbReaberto.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='whatsapp_fila'",
      );
      expect(tables.isNotEmpty, true);
    },
  );
}
