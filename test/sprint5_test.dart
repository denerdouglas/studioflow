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
import 'package:studioflow/models/domain/acesso.dart';
import 'package:studioflow/repositories/acesso_repository.dart';
import 'package:studioflow/repositories/compras_repository.dart';
import 'package:studioflow/repositories/infraestrutura_repository.dart';
import 'package:studioflow/services/session_controller.dart';

void main() {
  sqfliteFfiInit();

  group('Sprint 5 - produção e permissões granulares', () {
    late Database db;
    late AcessoRepository acesso;
    late UsuarioAcesso dono;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 5,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: DatabaseSchemaLatest.criar,
        ),
      );
      acesso = AcessoRepository(databaseProvider: () async => db);
      dono = await _criarComercio(acesso, 'dono@sprint5.test');
      SessionController.instance.entrar(dono);
    });

    tearDown(() async => db.close());

    test(
      'Dono possui todas as ações e funcionário recebe seleção exata',
      () async {
        expect(AcaoPermissao.values.every(dono.podeAcao), isTrue);
        await acesso.salvarUsuario(
          ator: dono,
          nome: 'Pessoa colaboradora',
          telefone: '11911112222',
          emailLogin: 'colaborador@sprint5.test',
          senha: 'Senha@456',
          funcao: FuncaoUsuario.colaborador,
          ativo: true,
          permissoes: {ModuloPermissao.lojaSalao, ModuloPermissao.estoque},
          acoes: {AcaoPermissao.visualizarEstoque},
        );
        final colaborador = await acesso.login(
          codigoComercio: dono.codigoComercio,
          emailLogin: 'colaborador@sprint5.test',
          senha: 'Senha@456',
          permanecerConectado: false,
        );
        expect(colaborador.podeAcao(AcaoPermissao.visualizarEstoque), isTrue);
        expect(colaborador.podeAcao(AcaoPermissao.cadastrarProduto), isFalse);
        expect(colaborador.podeAcao(AcaoPermissao.criarPedido), isFalse);
      },
    );

    test(
      'repositório bloqueia pedido sem permissão mesmo com módulo visível',
      () async {
        await acesso.salvarUsuario(
          ator: dono,
          nome: 'Operação estoque',
          telefone: '11922223333',
          emailLogin: 'estoque@sprint5.test',
          senha: 'Senha@789',
          funcao: FuncaoUsuario.colaborador,
          ativo: true,
          permissoes: {ModuloPermissao.lojaSalao},
          acoes: {AcaoPermissao.visualizarEstoque},
        );
        final usuario = await acesso.login(
          codigoComercio: dono.codigoComercio,
          emailLogin: 'estoque@sprint5.test',
          senha: 'Senha@789',
          permanecerConectado: false,
        );
        SessionController.instance.entrar(usuario);
        await expectLater(
          ComprasRepository(
            databaseProvider: () async => db,
          ).criarOrdem(itens: const []),
          throwsA(
            isA<StateError>().having(
              (erro) => erro.message,
              'mensagem',
              contains('criar pedido'),
            ),
          ),
        );
      },
    );

    test(
      'fila offline e unidade principal ficam isoladas por comércio',
      () async {
        final repo = InfraestruturaRepository(databaseProvider: () async => db);
        final estado = await repo.carregarEstado();
        expect(estado.unidadePrincipal.principal, isTrue);
        expect(estado.backendConfigurado, isFalse);
        await repo.enfileirar(
          entidade: 'clientes',
          entidadeId: 'cliente_local',
          operacao: 'atualizar',
          payload: const {'nome': 'Cliente local'},
        );
        expect(await repo.listarPendentes(), hasLength(1));

        final outro = await _criarComercio(acesso, 'outro@sprint5.test');
        SessionController.instance.entrar(outro);
        expect(await repo.listarPendentes(), isEmpty);
        expect(
          (await repo.carregarEstado()).unidadePrincipal.comercioId,
          outro.comercioId,
        );
      },
    );

    test('migração v4 para v5 preserva dados e cria backup lógico', () async {
      await db.close();
      final caminho = join(
        Directory.systemTemp.path,
        'studioflow_sprint5_migration.db',
      );
      await databaseFactoryFfi.deleteDatabase(caminho);
      addTearDown(() => databaseFactoryFfi.deleteDatabase(caminho));
      db = await databaseFactoryFfi.openDatabase(
        caminho,
        options: OpenDatabaseOptions(
          version: 4,
          onCreate: (db, _) async {
            await DatabaseSchema.criar(db, 1);
            await MigrationV2.executar(db, criarBackup: false);
            await MigrationV2Triggers.executar(db);
            await MigrationV3.executar(db, criarBackup: false);
            await MigrationV4.executar(db, criarBackup: false);
          },
        ),
      );
      final agora = DateTime(2026, 7, 22).toIso8601String();
      await db.insert('comercios', {
        'id': 'com_v4',
        'codigo_acesso': 'SFV40001',
        'nome': 'Comércio preservado',
        'nome_exibicao': 'Preservado',
        'responsavel': 'Dona',
        'telefone': '11999990000',
        'email': 'v4@test.local',
        'ativo': 1,
        'criado_em': agora,
        'atualizado_em': agora,
      });
      await db.insert('usuarios', {
        'id': 'usr_v4',
        'comercio_id': 'com_v4',
        'nome': 'Gerente legado',
        'telefone': '11999990001',
        'email_login': 'gerente@v4.test',
        'senha_hash': 'hash_preservado',
        'senha_salt': 'salt_preservado',
        'funcao': 'gerente',
        'ativo': 1,
        'criado_em': agora,
        'atualizado_em': agora,
      });
      await db.insert('permissoes', {
        'usuario_id': 'usr_v4',
        'modulo': 'estoque',
        'permitido': 1,
      });
      await db.close();

      db = await databaseFactoryFfi.openDatabase(
        caminho,
        options: OpenDatabaseOptions(
          version: 5,
          onUpgrade: DatabaseSchemaLatest.migrar,
        ),
      );
      expect(
        (await db.query(
          'usuarios',
          where: 'id = ?',
          whereArgs: ['usr_v4'],
        )).single['senha_hash'],
        'hash_preservado',
      );
      expect(
        await db.query(
          'permissoes_acoes',
          where: 'usuario_id = ? AND acao = ? AND permitido = 1',
          whereArgs: ['usr_v4', 'visualizarEstoque'],
        ),
        isNotEmpty,
      );
      expect(
        await db.query(
          'backups_logicos',
          where: 'versao_origem = ? AND tabela = ?',
          whereArgs: [4, 'usuarios'],
        ),
        isNotEmpty,
      );
      expect(
        (await db.query(
          'unidades',
          where: 'comercio_id = ?',
          whereArgs: ['com_v4'],
        )).single['principal'],
        1,
      );
    });
  });
}

Future<UsuarioAcesso> _criarComercio(AcessoRepository acesso, String email) =>
    acesso.cadastrarComercio(
      CadastroComercioEntrada(
        nomeComercio: 'Studio Sprint 5',
        nomeExibicao: 'Sprint 5',
        responsavel: 'Pessoa Dona',
        telefone: '11999990000',
        email: email,
        senha: 'Senha@123',
        permanecerConectado: false,
      ),
    );
