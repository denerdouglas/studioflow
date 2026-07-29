import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_schema.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/database/migrations/migration_v2_impl.dart';
import 'package:studioflow/database/migrations/migration_v2_triggers.dart';
import 'package:studioflow/database/migrations/migration_v3.dart';
import 'package:studioflow/database/migrations/migration_v4.dart';
import 'package:studioflow/database/migrations/migration_v5.dart';

void main() {
  sqfliteFfiInit();

  test('migração v5 para v6 preserva dados e cria backup lógico', () async {
    final path = join(Directory.systemTemp.path, 'studioflow_v5_to_v6.db');
    await databaseFactoryFfi.deleteDatabase(path);
    addTearDown(() => databaseFactoryFfi.deleteDatabase(path));
    var db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 5,
        onCreate: (database, _) async {
          await DatabaseSchema.criar(database, 1);
          await MigrationV2.executar(database, criarBackup: false);
          await MigrationV2Triggers.executar(database);
          await MigrationV3.executar(database, criarBackup: false);
          await MigrationV4.executar(database, criarBackup: false);
          await MigrationV5.executar(database, criarBackup: false);
        },
      ),
    );
    final now = DateTime.now().toIso8601String();
    await db.insert('comercios', {
      'id': 'legacy_commerce',
      'codigo_acesso': 'LEGACY01',
      'nome': 'Legado',
      'nome_exibicao': 'Legado',
      'responsavel': 'Owner',
      'telefone': '11999999999',
      'email': 'legacy@studioflow.test',
      'ativo': 1,
      'criado_em': now,
      'atualizado_em': now,
    });
    await db.insert('estoque', {
      'id': 'salon_legacy',
      'comercio_id': 'legacy_commerce',
      'nome': 'Uso interno',
      'categoria': 'Operacional',
      'tipo': 'consumivel',
      'quantidade_atual': 5,
      'estoque_minimo': 1,
      'unidade': 'un',
      'custo_unitario': 2,
      'data_cadastro': now,
    });
    await db.insert('estoque', {
      'id': 'store_legacy',
      'comercio_id': 'legacy_commerce',
      'nome': 'Produto vendido',
      'categoria': 'Varejo',
      'tipo': 'produto',
      'quantidade_atual': 5,
      'estoque_minimo': 1,
      'unidade': 'un',
      'custo_unitario': 2,
      'preco_venda': 10,
      'data_cadastro': now,
    });
    await db.close();

    db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 6,
        onUpgrade: DatabaseSchemaLatest.migrar,
      ),
    );
    addTearDown(db.close);

    final products = await db.query('estoque', orderBy: 'id');
    final byId = {for (final row in products) row['id']: row};
    expect(byId['salon_legacy']!['estoque_destino'], 'salao');
    expect(byId['store_legacy']!['estoque_destino'], 'loja');
    expect(await db.query('assinaturas'), hasLength(1));
    expect(
      await db.query(
        'backups_logicos',
        where: 'versao_origem = ? AND tabela = ?',
        whereArgs: [5, 'estoque'],
      ),
      isNotEmpty,
    );
  });
}
