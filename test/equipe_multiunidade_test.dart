import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/models/domain/acesso.dart';
import 'package:studioflow/repositories/acesso_repository.dart';
import 'package:studioflow/repositories/equipe_repository.dart';

void main() {
  sqfliteFfiInit();

  group('Equipe multiunidade', () {
    late Database db;
    late AcessoRepository acesso;
    late EquipeRepository equipe;
    late UsuarioAcesso dona;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 41,
          onCreate: DatabaseSchemaLatest.criar,
        ),
      );
      acesso = AcessoRepository(databaseProvider: () async => db);
      equipe = EquipeRepository(acesso: acesso);
      dona = await acesso.cadastrarComercio(
        const CadastroComercioEntrada(
          nomeComercio: 'Unidade A',
          nomeExibicao: 'Unidade A',
          responsavel: 'Dona',
          telefone: '11999999999',
          email: 'dona@teste.local',
          senha: 'Senha@123',
          permanecerConectado: false,
        ),
      );
      await _catalog(db, dona.comercioId);
    });

    tearDown(() => db.close());

    test(
      'aprovação salva cargo, áreas, serviços, comissão e permissões',
      () async {
        final request = await _request(
          equipe,
          dona.comercioId,
          'ana@teste.local',
        );
        await equipe.aprovar(
          ator: dona,
          solicitacaoId: request.id,
          funcao: FuncaoUsuario.gerente,
          permissoes: {ModuloPermissao.agenda, ModuloPermissao.estoque},
          acoes: {AcaoPermissao.agendaVerTodas},
          modalidadeIds: {'area_a'},
          servicos: {'servico_a': 35},
        );
        final user = (await acesso.listarUsuarios(
          dona.comercioId,
        )).singleWhere((item) => item.emailLogin == 'ana@teste.local');
        final detail = await equipe.detalhe(user);
        expect(user.funcao, FuncaoUsuario.gerente);
        expect(detail.modalidadeIds, {'area_a'});
        expect(detail.servicos, {'servico_a': 35});
        expect(detail.comissoesEfetivas['servico_a'], 35);
        expect(user.permissoes, {
          ModuloPermissao.agenda,
          ModuloPermissao.estoque,
        });
        expect(user.acoes, {AcaoPermissao.agendaVerTodas});
      },
    );

    test('Ver retorna configuração completa e comissão por fallback', () async {
      final user = await _approved(equipe, acesso, dona);
      final detail = await equipe.detalhe(user);
      expect(detail.unidade, 'Unidade A');
      expect(detail.usuario.nome, 'Colaboradora');
      expect(detail.usuario.ativo, isTrue);
      expect(detail.modalidadeIds, contains('area_a'));
      expect(detail.servicos, contains('servico_a'));
      expect(detail.comissoesEfetivas['servico_a'], 20);
    });

    test('Editar altera membership sem recriar conta', () async {
      final user = await _approved(equipe, acesso, dona);
      final before = await db.query('accounts');
      await equipe.editar(
        ator: dona,
        usuario: user,
        funcao: FuncaoUsuario.gerente,
        permissoes: {ModuloPermissao.agenda},
        acoes: {AcaoPermissao.agendaVerTodas},
        modalidadeIds: {'area_b'},
        servicos: {'servico_b': 42},
      );
      final after = await db.query('accounts');
      final membership = (await db.query(
        'business_memberships',
        where: 'usuario_id=?',
        whereArgs: [user.id],
      )).single;
      expect(after.length, before.length);
      expect(membership['role'], 'manager');
      expect((await equipe.detalhe(user)).modalidadeIds, {'area_b'});
    });

    test('remover serviço mantém vínculo e agendamento histórico', () async {
      final user = await _approved(equipe, acesso, dona);
      await _appointment(db, dona.comercioId, user.profissionalId!);
      await equipe.editar(
        ator: dona,
        usuario: user,
        funcao: user.funcao,
        permissoes: user.permissoes,
        acoes: user.acoes,
        modalidadeIds: const {},
        servicos: const {},
      );
      expect(
        (await db.query('agendamentos', where: 'id=?', whereArgs: ['ag_1'])),
        hasLength(1),
      );
      final link = (await db.query(
        'profissional_servicos',
        where: 'profissional_id=? AND servico_id=?',
        whereArgs: [user.profissionalId, 'servico_a'],
      )).single;
      expect(link['ativo'], 0);
    });

    test(
      'desativar preserva histórico, revoga acesso e reativar restaura',
      () async {
        final user = await _approved(equipe, acesso, dona);
        await _appointment(db, dona.comercioId, user.profissionalId!);
        final count = (await db.query('accounts')).length;
        await equipe.alterarAtivo(ator: dona, usuario: user, ativo: false);
        expect(await acesso.carregarUsuario(user.id), isNotNull);
        expect((await acesso.carregarUsuario(user.id))!.ativo, isFalse);
        expect(await db.query('agendamentos'), hasLength(1));
        await equipe.alterarAtivo(ator: dona, usuario: user, ativo: true);
        expect((await acesso.carregarUsuario(user.id))!.ativo, isTrue);
        expect((await db.query('accounts')).length, count);
      },
    );

    test('gerente não promove a si mesmo', () async {
      final user = await _approved(
        equipe,
        acesso,
        dona,
        role: FuncaoUsuario.gerente,
      );
      final manager = (await acesso.carregarUsuario(user.id))!;
      expect(
        () => equipe.editar(
          ator: manager,
          usuario: user,
          funcao: FuncaoUsuario.colaborador,
          permissoes: const {},
          acoes: const {},
          modalidadeIds: const {},
          servicos: const {},
        ),
        throwsStateError,
      );
    });

    test('edição na Unidade A não altera Unidade B', () async {
      final userA = await _approved(equipe, acesso, dona);
      final donaB = await acesso.cadastrarComercio(
        const CadastroComercioEntrada(
          nomeComercio: 'Unidade B',
          nomeExibicao: 'Unidade B',
          responsavel: 'Outra Dona',
          telefone: '11888888888',
          email: 'outra@teste.local',
          senha: 'Senha@123',
          permanecerConectado: false,
        ),
      );
      final beforeB = await db.query(
        'business_memberships',
        where: 'business_id=?',
        whereArgs: [donaB.comercioId],
      );
      await equipe.editar(
        ator: dona,
        usuario: userA,
        funcao: FuncaoUsuario.gerente,
        permissoes: {ModuloPermissao.agenda},
        acoes: {AcaoPermissao.agendaVerTodas},
        modalidadeIds: const {},
        servicos: const {},
      );
      expect(
        await db.query(
          'business_memberships',
          where: 'business_id=?',
          whereArgs: [donaB.comercioId],
        ),
        beforeB,
      );
    });
  });
}

Future<SolicitacaoEquipe> _request(
  EquipeRepository repository,
  String businessId,
  String login,
) async {
  await repository.solicitarAcesso(
    businessId: businessId,
    nome: 'Colaboradora',
    telefone: '11777777777',
    login: login,
    senha: 'Senha@123',
  );
  return (await repository.listarSolicitacoes(businessId)).single;
}

Future<UsuarioGerenciavel> _approved(
  EquipeRepository repository,
  AcessoRepository access,
  UsuarioAcesso owner, {
  FuncaoUsuario role = FuncaoUsuario.colaborador,
}) async {
  final request = await _request(
    repository,
    owner.comercioId,
    'colab@teste.local',
  );
  await repository.aprovar(
    ator: owner,
    solicitacaoId: request.id,
    funcao: role,
    permissoes: {ModuloPermissao.agenda},
    acoes: role == FuncaoUsuario.gerente
        ? {AcaoPermissao.agendaVerTodas}
        : {AcaoPermissao.gerenciarAgenda},
    modalidadeIds: {'area_a'},
    servicos: {'servico_a': null},
  );
  return (await access.listarUsuarios(
    owner.comercioId,
  )).singleWhere((item) => item.emailLogin == 'colab@teste.local');
}

Future<void> _catalog(Database db, String businessId) async {
  final now = DateTime.now().toUtc().toIso8601String();
  for (final id in ['a', 'b']) {
    await db.insert('modalidades_estabelecimento', {
      'id': 'area_$id',
      'comercio_id': businessId,
      'nome': 'Área $id',
      'nome_normalizado': 'area_$id',
      'ordem': 0,
      'favorita': 0,
      'exibir_home': 1,
      'ativa': 1,
      'personalizada': 1,
      'criado_em': now,
      'atualizado_em': now,
    });
    await db.insert('servicos', {
      'id': 'servico_$id',
      'nome': 'Serviço $id',
      'categoria': 'Teste',
      'preco': 100,
      'duracao_minutos': 60,
      'ativo': 1,
      'comissao_percentual': 20,
      'custo_estimado': 0,
      'data_cadastro': now,
      'business_id': businessId,
      'created_at': now,
      'updated_at': now,
    });
  }
}

Future<void> _appointment(
  Database db,
  String businessId,
  String professionalId,
) {
  final now = DateTime.now().toUtc();
  return db.insert('agendamentos', {
    'id': 'ag_1',
    'comercio_id': businessId,
    'cliente_id': 'cliente_historico',
    'profissional_id': professionalId,
    'servico_id': 'servico_a',
    'inicio': now.subtract(const Duration(days: 2)).toIso8601String(),
    'fim': now.subtract(const Duration(days: 2, hours: -1)).toIso8601String(),
    'status': 'concluido',
    'valor_servico': 100,
    'data_criacao': now.toIso8601String(),
    'business_id': businessId,
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
  });
}
