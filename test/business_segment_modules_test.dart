import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/models/domain/acesso.dart';
import 'package:studioflow/models/domain/business_profile.dart';
import 'package:studioflow/registry/dashboard_configuration.dart';
import 'package:studioflow/repositories/acesso_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('personalização real por segmento', () {
    test('manicure e somente loja não recebem configuração igual', () {
      final manicure = BusinessModuleConfiguration.defaultsFor(
        TipoEstabelecimento.nailDesigner,
      );
      final loja = BusinessModuleConfiguration.defaultsFor(
        TipoEstabelecimento.outro,
        somenteLoja: true,
      );

      expect(manicure.possui(BusinessModule.agenda), isTrue);
      expect(manicure.possui(BusinessModule.servicos), isTrue);
      expect(manicure.possui(BusinessModule.loja), isFalse);
      expect(loja.possui(BusinessModule.loja), isTrue);
      expect(loja.possui(BusinessModule.agenda), isFalse);
      expect(loja.possui(BusinessModule.servicos), isFalse);
      expect(manicure.toJson(), isNot(loja.toJson()));
    });

    test('defaults cobrem todos os segmentos suportados', () {
      final salao = _defaults(TipoEstabelecimento.salao);
      final manicure = _defaults(TipoEstabelecimento.nailDesigner);
      final barbearia = _defaults(TipoEstabelecimento.barbearia);
      final cilios = _defaults(TipoEstabelecimento.lashDesigner);
      final estetica = _defaults(TipoEstabelecimento.estetica);
      final outro = _defaults(TipoEstabelecimento.outro);
      final loja = BusinessModuleConfiguration.defaultsFor(
        TipoEstabelecimento.outro,
        somenteLoja: true,
      );

      expect(salao.possui(BusinessModule.loja), isTrue);
      expect(manicure.possui(BusinessModule.produtos), isTrue);
      expect(barbearia.possui(BusinessModule.equipe), isTrue);
      expect(cilios.possui(BusinessModule.equipe), isFalse);
      expect(estetica.possui(BusinessModule.agenda), isTrue);
      expect(outro.ativos, containsAll(BusinessModule.values));
      expect(loja.possui(BusinessModule.fornecedores), isTrue);
      expect(loja.possui(BusinessModule.equipe), isFalse);
    });

    test('conta legada sem JSON mantém experiência completa', () {
      final legacy = _user(moduleConfiguration: null);
      expect(legacy.businessProfile.explicitConfiguration, isFalse);
      expect(
        legacy.businessProfile.modules.ativos,
        containsAll(BusinessModule.values),
      );
    });

    test('layout e rotas visuais seguem módulos ativos', () {
      final manicure = DashboardConfiguration.forModules(
        _defaults(TipoEstabelecimento.nailDesigner),
      );
      final loja = DashboardConfiguration.forModules(
        BusinessModuleConfiguration.defaultsFor(
          TipoEstabelecimento.outro,
          somenteLoja: true,
        ),
      );
      expect(manicure.layout, contains('agenda'));
      expect(loja.layout, isNot(contains('agenda')));
      expect(loja.layout, contains('caixa'));
    });

    test(
      'ativação posterior altera configuração sem apagar módulos restantes',
      () {
        final original = _defaults(TipoEstabelecimento.nailDesigner);
        final enabled = original.alterar(BusinessModule.loja, true);
        expect(enabled.possui(BusinessModule.loja), isTrue);
        expect(enabled.possui(BusinessModule.agenda), isTrue);
        expect(original.possui(BusinessModule.loja), isFalse);
      },
    );

    test(
      'logout/login e duas contas preservam isolamento por comercio_id',
      () async {
        final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
        addTearDown(db.close);
        await DatabaseSchemaLatest.criar(db, 46);
        final repository = AcessoRepository(databaseProvider: () async => db);

        final manicure = await repository.cadastrarComercio(
          _entry('manicure', TipoEstabelecimento.nailDesigner),
        );
        final loja = await repository.cadastrarComercio(
          _entry('loja', TipoEstabelecimento.outro, somenteLoja: true),
        );

        final manicureReloaded = await repository.carregarUsuario(manicure.id);
        final lojaReloaded = await repository.carregarUsuario(loja.id);
        expect(manicureReloaded!.moduloAtivo(BusinessModule.agenda), isTrue);
        expect(manicureReloaded.moduloAtivo(BusinessModule.loja), isFalse);
        expect(lojaReloaded!.moduloAtivo(BusinessModule.loja), isTrue);
        expect(lojaReloaded.moduloAtivo(BusinessModule.agenda), isFalse);
        expect(manicureReloaded.comercioId, isNot(lojaReloaded.comercioId));
      },
    );

    test('desativar módulo preserva dados persistidos', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await DatabaseSchemaLatest.criar(db, 46);
      final repository = AcessoRepository(databaseProvider: () async => db);
      final user = await repository.cadastrarComercio(
        _entry('salao', TipoEstabelecimento.salao),
      );
      await db.insert('clientes', {
        'id': 'cliente_preservado',
        'comercio_id': user.comercioId,
        'nome': 'Cliente preservada',
        'whatsapp': '11999999999',
        'telefone': '11999999999',
        'ativo': 1,
        'data_cadastro': DateTime.now().toIso8601String(),
      });
      final disabled = user.businessProfile.modules.alterar(
        BusinessModule.clientes,
        false,
      );
      await db.update(
        'comercios',
        {'modulos_configuracao_json': disabled.toJson()},
        where: 'id = ?',
        whereArgs: [user.comercioId],
      );
      final rows = await db.query(
        'clientes',
        where: 'comercio_id = ?',
        whereArgs: [user.comercioId],
      );
      expect(rows.single['nome'], 'Cliente preservada');
    });
  });
}

BusinessModuleConfiguration _defaults(TipoEstabelecimento segment) =>
    BusinessModuleConfiguration.defaultsFor(segment);

CadastroComercioEntrada _entry(
  String suffix,
  TipoEstabelecimento segment, {
  bool somenteLoja = false,
}) => CadastroComercioEntrada(
  nomeComercio: 'Negócio $suffix',
  nomeExibicao: 'Negócio $suffix',
  responsavel: 'Dona $suffix',
  telefone: '11999999999',
  email: '$suffix@studioflow.test',
  senha: 'SenhaSegura123',
  permanecerConectado: false,
  tipoEstabelecimento: segment,
  moduloLojaAtivo: true,
  moduloServicosAtivo: !somenteLoja,
  moduleConfiguration: BusinessModuleConfiguration.defaultsFor(
    segment,
    somenteLoja: somenteLoja,
  ),
);

UsuarioAcesso _user({BusinessModuleConfiguration? moduleConfiguration}) =>
    UsuarioAcesso(
      id: 'user',
      comercioId: 'business',
      codigoComercio: 'CODE',
      nomeComercio: 'Legado',
      nomeExibicao: 'Legado',
      nome: 'Dona',
      telefone: '11999999999',
      emailLogin: 'legacy@studioflow.test',
      funcao: FuncaoUsuario.dono,
      ativo: true,
      permissoes: ModuloPermissao.values.toSet(),
      acoes: AcaoPermissao.values.toSet(),
      moduleConfiguration: moduleConfiguration,
    );
