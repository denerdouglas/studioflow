import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../core/constants/database_constants.dart';
import 'database_schema_latest.dart';

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

    return await openDatabase(
      path,
      version: DatabaseConstants.versao,
      onCreate: DatabaseSchemaLatest.criar,
      onUpgrade: DatabaseSchemaLatest.migrar,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
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
