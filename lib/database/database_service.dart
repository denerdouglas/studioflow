import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../core/constants/database_constants.dart';
import 'database_schema_latest.dart';
import 'database_schema_verifier.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._();

  DatabaseService._();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    _database = await _initDatabase();

    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();

    final path = join(dbPath, DatabaseConstants.nomeArquivo);

    final db = await openDatabase(
      path,
      version: DatabaseConstants.versao,
      onCreate: DatabaseSchemaLatest.criar,
      onUpgrade: DatabaseSchemaLatest.migrar,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );

    // Reparo idempotente de schema, previne furos de migrations antigas.
    await DatabaseSchemaVerifier.repair(db);

    // Validação preventiva crítica
    await _validarSchemaCritico(db);

    return db;
  }

  Future<void> _validarSchemaCritico(Database db) async {
    final colunas = await db.rawQuery('PRAGMA table_info(estoque)');
    final temBusinessId = colunas.any((c) => c['name'] == 'business_id');

    if (!temBusinessId) {
      throw Exception(
        'FALHA CRÍTICA DE SCHEMA: A coluna business_id não existe na tabela estoque '
        'mesmo após o DatabaseSchemaVerifier.repair. '
        'O aplicativo não pode iniciar para evitar corrupção de dados.',
      );
    }
  }

  Future<void> fecharBanco() async {
    final db = _database;

    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  Future<void> limparBanco() async {
    final dbPath = await getDatabasesPath();

    final path = join(dbPath, DatabaseConstants.nomeArquivo);

    await fecharBanco();
    await deleteDatabase(path);
  }
}
