import 'package:sqflite/sqflite.dart';

import 'database_schema.dart';
import 'migrations/migration_v2_impl.dart';
import 'migrations/migration_v2_triggers.dart';
import 'migrations/migration_v3.dart';
import 'migrations/migration_v4.dart';
import 'migrations/migration_v5.dart';
import 'migrations/migration_v6.dart';
import 'migrations/migration_v7.dart';
import 'migrations/migration_v8.dart';
import 'migrations/migration_v9.dart';
import 'migrations/migration_v10.dart';
import 'migrations/migration_v11.dart';
import 'migrations/migration_v12.dart';
import 'migrations/migration_v13.dart';
import 'migrations/migration_v14.dart';
import 'migrations/migration_v15.dart';

import 'migrations/migration_v16.dart';
import 'migrations/migration_v17.dart';
import 'migrations/migration_v18.dart';
import 'migrations/migration_v19.dart';
import 'migrations/migration_v20.dart';
import 'migrations/migration_v21.dart';
import 'migrations/migration_v22.dart';
import 'migrations/migration_v23.dart';
import 'migrations/migration_v24.dart';
import 'migrations/migration_v25.dart';
import 'migrations/migration_v26.dart';
import 'migrations/migration_v27.dart';
import 'migrations/migration_v28.dart';
import 'migrations/migration_v29.dart';

abstract final class DatabaseSchemaLatest {
  static Future<void> criar(Database db, int version) async {
    await DatabaseSchema.criar(db, 1);
    await MigrationV2.executar(db, criarBackup: false);
    await MigrationV2Triggers.executar(db);
    await MigrationV3.executar(db, criarBackup: false);
    await MigrationV4.executar(db, criarBackup: false);
    await MigrationV5.executar(db, criarBackup: false);
    await MigrationV6.executar(db, criarBackup: false);
    await MigrationV7.executar(db, criarBackup: false);
    await MigrationV8.executar(db, criarBackup: false);
    await MigrationV9.executar(db, criarBackup: false);
    await MigrationV10.executar(db, criarBackup: false);
    await MigrationV11.executar(db, criarBackup: false);
    await MigrationV12.executar(db, criarBackup: false);
    await MigrationV13.executar(db, criarBackup: false);
    await MigrationV14.executar(db, criarBackup: false);
    await MigrationV15.executar(db, criarBackup: false);
    await MigrationV16.executar(db, criarBackup: false);
    await MigrationV17.executar(db);
    await MigrationV18.executar(db);
    await MigrationV19.executar(db);
    await MigrationV20.executar(db);
    await MigrationV21.executar(db);
    await MigrationV22.executar(db);
    await MigrationV23.executar(db);
    await MigrationV24.executar(db);
    await MigrationV25.executar(db);
    await MigrationV26.executar(db);
    await MigrationV27.executar(db);
    await MigrationV28.executar(db);
    await MigrationV29.executar(db);
  }

  static Future<void> migrar(
    Database db,
    int versaoAnterior,
    int novaVersao,
  ) async {
    if (versaoAnterior < 2 && novaVersao >= 2) {
      await MigrationV2.executar(db, criarBackup: true);
      await MigrationV2Triggers.executar(db);
    }
    if (versaoAnterior < 3 && novaVersao >= 3) {
      await MigrationV3.executar(db, criarBackup: true);
    }
    if (versaoAnterior < 4 && novaVersao >= 4) {
      await MigrationV4.executar(db, criarBackup: true);
    }
    if (versaoAnterior < 5 && novaVersao >= 5) {
      await MigrationV5.executar(db, criarBackup: true);
    }
    if (versaoAnterior < 6 && novaVersao >= 6) {
      await MigrationV6.executar(db, criarBackup: true);
    }
    if (versaoAnterior < 7 && novaVersao >= 7) {
      await MigrationV7.executar(db, criarBackup: true);
    }
    if (versaoAnterior < 8 && novaVersao >= 8) {
      await MigrationV8.executar(db, criarBackup: true);
    }
    if (versaoAnterior < 9 && novaVersao >= 9) {
      await MigrationV9.executar(db, criarBackup: true);
    }
    if (versaoAnterior < 10 && novaVersao >= 10) {
      await MigrationV10.executar(db, criarBackup: true);
    }
    if (versaoAnterior < 11 && novaVersao >= 11) {
      await MigrationV11.executar(db, criarBackup: true);
    }
    if (versaoAnterior < 12 && novaVersao >= 12) {
      await MigrationV12.executar(db, criarBackup: true);
    }
    if (versaoAnterior < 13 && novaVersao >= 13) {
      await MigrationV13.executar(db, criarBackup: true);
    }
    if (versaoAnterior < 14 && novaVersao >= 14) {
      await MigrationV14.executar(db, criarBackup: true);
    }
    if (versaoAnterior < 15 && novaVersao >= 15) {
      await MigrationV15.executar(db, criarBackup: true);
    }
    if (versaoAnterior < 16 && novaVersao >= 16) {
      await MigrationV16.executar(db, criarBackup: true);
    }
    if (versaoAnterior < 17 && novaVersao >= 17) {
      await MigrationV17.executar(db);
    }
    if (versaoAnterior < 18 && novaVersao >= 18) {
      await MigrationV18.executar(db, criarBackup: true);
    }
    if (versaoAnterior < 19 && novaVersao >= 19) {
      await MigrationV19.executar(db, criarBackup: true);
    }
    if (versaoAnterior < 20 && novaVersao >= 20) {
      await MigrationV20.executar(db);
    }
    if (versaoAnterior < 21 && novaVersao >= 21) {
      await MigrationV21.executar(db);
    }
    if (versaoAnterior < 22 && novaVersao >= 22) {
      await MigrationV22.executar(db);
    }
    if (versaoAnterior < 23 && novaVersao >= 23) {
      await MigrationV23.executar(db);
    }
    if (versaoAnterior < 24 && novaVersao >= 24) {
      await MigrationV24.executar(db);
    }
    if (versaoAnterior < 25 && novaVersao >= 25) {
      await MigrationV25.executar(db);
    }
    if (versaoAnterior < 26 && novaVersao >= 26) {
      await MigrationV26.executar(db);
    }
    if (versaoAnterior < 27 && novaVersao >= 27) {
      await MigrationV27.executar(db);
    }
    if (versaoAnterior < 28 && novaVersao >= 28) {
      await MigrationV28.executar(db);
    }
    if (versaoAnterior < 29 && novaVersao >= 29) {
      await MigrationV29.executar(db);
    }
  }
}
