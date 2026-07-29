import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/models/domain/acesso.dart';
import 'package:studioflow/models/domain/aparencia.dart';
import 'package:studioflow/repositories/acesso_repository.dart';
import 'package:studioflow/repositories/aparencia_repository.dart';
import 'package:studioflow/screens/acesso_page.dart';

void main() {
  sqfliteFfiInit();

  group('Sprint 6 continuação - acesso multiestabelecimento', () {
    late Database db;
    late AcessoRepository acesso;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 8,
          onConfigure: (database) =>
              database.execute('PRAGMA foreign_keys = ON'),
          onCreate: DatabaseSchemaLatest.criar,
        ),
      );
      acesso = AcessoRepository(databaseProvider: () async => db);
    });

    tearDown(() => db.close());

    testWidgets('login não solicita ID do estabelecimento', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: AcessoPage(carregarCadastroLegado: false)),
      );
      expect(find.text('ID do comércio'), findsNothing);
      expect(find.text('E-mail ou login'), findsOneWidget);
      expect(find.text('Esqueci minha senha'), findsOneWidget);
    });

    test(
      'identifica duas contas e permite escolher o estabelecimento',
      () async {
        final primeira = await acesso.cadastrarComercio(
          const CadastroComercioEntrada(
            nomeComercio: 'Studio A',
            nomeExibicao: 'Studio A',
            responsavel: 'Rafa',
            telefone: '11999991234',
            email: 'rafa@studio.test',
            senha: '123456',
            permanecerConectado: true,
            tipoEstabelecimento: TipoEstabelecimento.salao,
          ),
        );
        final segunda = await acesso.cadastrarComercio(
          const CadastroComercioEntrada(
            nomeComercio: 'Barbearia B',
            nomeExibicao: 'Barbearia B',
            responsavel: 'Rafa',
            telefone: '11999991234',
            email: 'rafa@studio.test',
            senha: '123456',
            permanecerConectado: true,
            tipoEstabelecimento: TipoEstabelecimento.barbearia,
          ),
        );

        final contas = await acesso.autenticar(
          login: 'RAFA@STUDIO.TEST',
          senha: '123456',
        );
        expect(
          contas.map((item) => item.comercioId),
          containsAll([primeira.comercioId, segunda.comercioId]),
        );
        expect(
          contas.map((item) => item.tipoEstabelecimento),
          contains(TipoEstabelecimento.barbearia),
        );

        await acesso.iniciarSessao(
          usuario: contas.firstWhere(
            (item) => item.comercioId == segunda.comercioId,
          ),
          permanecerConectado: true,
        );
        expect(
          (await acesso.restaurarSessao())!.comercioId,
          segunda.comercioId,
        );
      },
    );

    test(
      'recuperação local valida telefone, troca hash e invalida sessão',
      () async {
        final usuario = await acesso.cadastrarComercio(
          const CadastroComercioEntrada(
            nomeComercio: 'Studio Seguro',
            nomeExibicao: 'Studio Seguro',
            responsavel: 'Dona',
            telefone: '(11) 98888-7777',
            email: 'dona@studio.test',
            senha: 'senha-antiga',
            permanecerConectado: true,
          ),
        );
        await expectLater(
          acesso.redefinirSenhaLocal(
            usuarioId: usuario.id,
            telefone: '11900000000',
            novaSenha: 'senha-nova',
          ),
          throwsStateError,
        );
        await acesso.redefinirSenhaLocal(
          usuarioId: usuario.id,
          telefone: '11 98888-7777',
          novaSenha: 'senha-nova',
        );
        expect(await acesso.restaurarSessao(), isNull);
        expect(
          await acesso.autenticar(
            login: 'dona@studio.test',
            senha: 'senha-nova',
          ),
          hasLength(1),
        );
        final auditoria = await db.query(
          'recuperacoes_senha',
          orderBy: 'criado_em',
        );
        expect(auditoria, hasLength(2));
        expect(auditoria.last['sucesso'], 1);
      },
    );

    test('isola clientes e contas entre três estabelecimentos', () async {
      final comercios = <String>[];
      for (var indice = 1; indice <= 3; indice++) {
        final usuario = await acesso.cadastrarComercio(
          CadastroComercioEntrada(
            nomeComercio: 'Estabelecimento $indice',
            nomeExibicao: 'Unidade $indice',
            responsavel: 'Responsável $indice',
            telefone: '1199999000$indice',
            email: 'multi@studio.test',
            senha: '123456',
            permanecerConectado: false,
          ),
        );
        comercios.add(usuario.comercioId);
        final agora = DateTime.now().toUtc().toIso8601String();
        await db.insert('clientes', {
          'id': 'cliente_$indice',
          'comercio_id': usuario.comercioId,
          'nome': 'Cliente da unidade $indice',
          'whatsapp': '11988887777',
          'ativo': 1,
          'data_cadastro': agora,
          'total_atendimentos': 0,
          'total_gasto': 0,
          'pontos_fidelidade': 0,
        });
      }

      final contas = await acesso.autenticar(
        login: 'multi@studio.test',
        senha: '123456',
      );
      expect(contas, hasLength(3));
      for (final comercioId in comercios) {
        final clientes = await db.query(
          'clientes',
          where: 'comercio_id = ?',
          whereArgs: [comercioId],
        );
        expect(clientes, hasLength(1));
        expect(clientes.single['comercio_id'], comercioId);
      }
    });
    test('aparência fica isolada e persistida por estabelecimento', () async {
      final usuario = await acesso.cadastrarComercio(
        const CadastroComercioEntrada(
          nomeComercio: 'Nail Rosa',
          nomeExibicao: 'Nail Rosa',
          responsavel: 'Ana',
          telefone: '11999990000',
          email: 'ana@nail.test',
          senha: '123456',
          permanecerConectado: false,
          tipoEstabelecimento: TipoEstabelecimento.nailDesigner,
        ),
      );
      final repository = AparenciaRepository(databaseProvider: () async => db);
      await repository.salvar(
        ConfiguracaoAparencia(
          comercioId: usuario.comercioId,
          logoPath: '/dados/logo.png',
          corPrincipal: '#AA3377',
          corSecundaria: '#CC6699',
          corDestaque: '#F0BBDD',
          temaModo: 'escuro',
          temaAutomatico: false,
        ),
      );
      final recarregada = await repository.carregar(usuario.comercioId);
      expect(recarregada.corPrincipal, '#AA3377');
      expect(recarregada.temaModo, 'escuro');
      expect(recarregada.logoPath, '/dados/logo.png');
    });
  });
}
