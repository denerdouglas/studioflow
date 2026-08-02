import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_schema.dart';
import 'package:studioflow/database/migrations/migration_v2_impl.dart';
import 'package:studioflow/database/migrations/migration_v2_triggers.dart';
import 'package:studioflow/database/migrations/migration_v3.dart';
import 'package:studioflow/database/migrations/migration_v4.dart';
import 'package:studioflow/database/migrations/migration_v5.dart';
import 'package:studioflow/database/migrations/migration_v6.dart';
import 'package:studioflow/database/migrations/migration_v7.dart';
import 'package:studioflow/database/migrations/migration_v8.dart';
import 'package:studioflow/database/migrations/migration_v9.dart';
import 'package:studioflow/database/migrations/migration_v10.dart';
import 'package:studioflow/database/migrations/migration_v11.dart';
import 'package:studioflow/database/migrations/migration_v12.dart';
import 'package:studioflow/database/migrations/migration_v13.dart';
import 'package:studioflow/database/migrations/migration_v14.dart';
import 'package:studioflow/database/migrations/migration_v15.dart';
import 'package:studioflow/database/migrations/migration_v16.dart';
import 'package:studioflow/database/migrations/migration_v17.dart';
import 'package:studioflow/database/migrations/migration_v18.dart';
import 'package:studioflow/database/migrations/migration_v19.dart';

class TestDatabaseFactory {
  static Future<Database> createAtVersion(int version) async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    if (version >= 1) await DatabaseSchema.criar(db, 1);
    if (version >= 2) {
      await MigrationV2.executar(db, criarBackup: false);
      await MigrationV2Triggers.executar(db);
    }
    if (version >= 3) await MigrationV3.executar(db, criarBackup: false);
    if (version >= 4) await MigrationV4.executar(db, criarBackup: false);
    if (version >= 5) await MigrationV5.executar(db, criarBackup: false);
    if (version >= 6) await MigrationV6.executar(db, criarBackup: false);
    if (version >= 7) await MigrationV7.executar(db, criarBackup: false);
    if (version >= 8) await MigrationV8.executar(db, criarBackup: false);
    if (version >= 9) await MigrationV9.executar(db, criarBackup: false);
    if (version >= 10) await MigrationV10.executar(db, criarBackup: false);
    if (version >= 11) await MigrationV11.executar(db, criarBackup: false);
    if (version >= 12) await MigrationV12.executar(db, criarBackup: false);
    if (version >= 13) await MigrationV13.executar(db, criarBackup: false);
    if (version >= 14) await MigrationV14.executar(db, criarBackup: false);
    if (version >= 15) await MigrationV15.executar(db, criarBackup: false);
    if (version >= 16) await MigrationV16.executar(db, criarBackup: false);
    if (version >= 17) await MigrationV17.executar(db);
    if (version >= 18) await MigrationV18.executar(db);
    if (version >= 19) await MigrationV19.executar(db);
    return db;
  }
}
