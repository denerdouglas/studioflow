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
import 'package:studioflow/database/migrations/migration_v6.dart';

void main() {
  sqfliteFfiInit();

  test('migração v6 para v7 preserva cliente, sessão e configuração', () async {
    final path = join(Directory.systemTemp.path, 'studioflow_v6_to_v7.db');
    await databaseFactoryFfi.deleteDatabase(path);
    addTearDown(() => databaseFactoryFfi.deleteDatabase(path));
    var db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 6,
        onCreate: (database, _) async {
          await DatabaseSchema.criar(database, 1);
          await MigrationV2.executar(database, criarBackup: false);
          await MigrationV2Triggers.executar(database);
          await MigrationV3.executar(database, criarBackup: false);
          await MigrationV4.executar(database, criarBackup: false);
          await MigrationV5.executar(database, criarBackup: false);
          await MigrationV6.executar(database, criarBackup: false);
        },
      ),
    );
    final now = DateTime.now().toIso8601String();
    await db.insert('comercios', {
      'id': 'legacy',
      'codigo_acesso': 'LEGACY61',
      'nome': 'Salão legado',
      'nome_exibicao': 'Salão legado',
      'responsavel': 'Rafa',
      'telefone': '11999991234',
      'email': 'rafa@legacy.test',
      'ativo': 1,
      'criado_em': now,
      'atualizado_em': now,
    });
    await db.insert('usuarios', {
      'id': 'owner',
      'comercio_id': 'legacy',
      'nome': 'Rafa',
      'telefone': '11999991234',
      'email_login': 'rafa@legacy.test',
      'senha_hash': 'hash-de-teste',
      'senha_salt': 'salt-de-teste',
      'funcao': 'dono',
      'ativo': 1,
      'criado_em': now,
      'atualizado_em': now,
    });
    await db.insert('sessoes', {
      'id': 'session',
      'usuario_id': 'owner',
      'comercio_id': 'legacy',
      'criada_em': now,
      'ultimo_acesso': now,
      'persistente': 1,
      'ativa': 1,
    });
    await db.insert('clientes', {
      'id': 'client',
      'comercio_id': 'legacy',
      'nome': 'Cliente preservada',
      'whatsapp': '11988887777',
      'ativo': 1,
      'data_cadastro': now,
      'total_atendimentos': 0,
      'total_gasto': 0,
      'pontos_fidelidade': 0,
    });
    await db.insert('configuracoes', {
      'chave': 'legacy.whatsapp',
      'valor': '11999991234',
      'comercio_id': 'legacy',
    });
    await db.close();

    db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 7,
        onUpgrade: DatabaseSchemaLatest.migrar,
      ),
    );
    addTearDown(db.close);

    expect(
      await db.query('clientes', where: 'id = ?', whereArgs: ['client']),
      hasLength(1),
    );
    expect(
      await db.query(
        'sessoes',
        where: 'id = ? AND ativa = 1',
        whereArgs: ['session'],
      ),
      hasLength(1),
    );
    expect(
      await db.query(
        'configuracoes',
        where: 'chave = ?',
        whereArgs: ['legacy.whatsapp'],
      ),
      hasLength(1),
    );
    expect(
      await db.query(
        'modelos_mensagens',
        where: 'comercio_id = ?',
        whereArgs: ['legacy'],
      ),
      hasLength(greaterThanOrEqualTo(18)),
    );
    expect(
      await db.query(
        'backups_logicos',
        where: 'versao_origem = ?',
        whereArgs: [6],
      ),
      isNotEmpty,
    );
  });
}
