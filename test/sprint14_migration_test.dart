import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/database/migrations/migration_v11.dart';
import 'package:studioflow/models/domain/acesso.dart';
import 'package:studioflow/repositories/acesso_repository.dart';

void main() {
  sqfliteFfiInit();

  test('migração v11 faz backup lógico e preserva dados existentes', () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 11,
        onCreate: DatabaseSchemaLatest.criar,
      ),
    );
    addTearDown(db.close);
    final acesso = AcessoRepository(databaseProvider: () async => db);
    final dono = await acesso.cadastrarComercio(
      const CadastroComercioEntrada(
        nomeComercio: 'Studio Migração',
        nomeExibicao: 'Studio Migração',
        responsavel: 'Responsável',
        telefone: '11999999999',
        email: 'migracao@studioflow.test',
        senha: 'Senha@123',
        permanecerConectado: false,
      ),
    );
    await db.insert('clientes', {
      'id': 'cliente_preservado',
      'comercio_id': dono.comercioId,
      'nome': 'Cliente preservado',
      'whatsapp': '11988887777',
      'ativo': 1,
      'data_cadastro': DateTime.now().toIso8601String(),
      'total_atendimentos': 0,
      'total_gasto': 0,
      'pontos_fidelidade': 0,
    });

    await MigrationV11.executar(db, criarBackup: true);

    expect(
      await db.query(
        'clientes',
        where: 'id=?',
        whereArgs: ['cliente_preservado'],
      ),
      hasLength(1),
    );
    expect(
      await db.query('backups_logicos', where: 'versao_origem=10'),
      hasLength(greaterThanOrEqualTo(7)),
    );
    expect(
      await db.query(
        'permissoes_acoes',
        where: 'usuario_id=? AND acao=? AND permitido=1',
        whereArgs: [dono.id, 'visualizarPacotes'],
      ),
      hasLength(1),
    );
  });
}
