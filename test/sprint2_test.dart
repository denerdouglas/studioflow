import 'dart:io';

import 'package:path/path.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_schema.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/models/domain/acesso.dart';
import 'package:studioflow/models/domain/configuracao_comercio.dart';
import 'package:studioflow/repositories/acesso_repository.dart';
import 'package:studioflow/repositories/configuracoes_repository.dart';
import 'package:studioflow/screens/acesso_page.dart';
import 'package:studioflow/services/ia_local_service.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('tela inicial oferece login e cadastro de comércio', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: [],
        home: AcessoPage(carregarCadastroLegado: false),
      ),
    );
    await tester.pump();

    expect(find.text('Entrar'), findsWidgets);
    expect(find.text('Cadastrar comércio'), findsOneWidget);
    expect(find.text('ID do comércio'), findsNothing);
    expect(find.text('E-mail ou login'), findsOneWidget);
  });

  group('banco e acesso da Sprint 2', () {
    late Database db;
    late AcessoRepository acesso;
    late ConfiguracoesRepository configuracoes;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 2,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: DatabaseSchemaLatest.criar,
        ),
      );
      acesso = AcessoRepository(databaseProvider: () async => db);
      configuracoes = ConfiguracoesRepository(databaseProvider: () async => db);
    });

    tearDown(() async => db.close());

    test('migração v1 cria backup lógico e preserva registros', () async {
      await db.close();
      final caminho = join(
        Directory.systemTemp.path,
        'studioflow_migracao_.db',
      );
      addTearDown(() => databaseFactoryFfi.deleteDatabase(caminho));
      await databaseFactoryFfi.deleteDatabase(caminho);
      db = await databaseFactoryFfi.openDatabase(
        caminho,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: DatabaseSchema.criar,
        ),
      );
      await db.insert('clientes', {
        'id': 'cliente_legado',
        'nome': 'Cliente preservado',
        'whatsapp': '11999999999',
        'data_cadastro': DateTime(2026).toIso8601String(),
      });
      await db.close();
      db = await databaseFactoryFfi.openDatabase(
        caminho,
        options: OpenDatabaseOptions(
          version: 2,
          onUpgrade: DatabaseSchemaLatest.migrar,
        ),
      );

      final clientes = await db.query('clientes');
      final backups = await db.query(
        'backups_logicos',
        where: 'tabela = ?',
        whereArgs: ['clientes'],
      );
      expect(clientes.single['id'], 'cliente_legado');
      expect(clientes.single['comercio_id'], 'comercio_legado');
      expect(backups, isNotEmpty);
    });

    test('cadastro, login, sessão e logout do dono', () async {
      final dono = await _criarComercio(acesso);

      expect(dono.funcao, FuncaoUsuario.dono);
      expect(dono.codigoComercio, startsWith('SF'));
      expect(dono.permissoes, containsAll(ModuloPermissao.values));

      final senhaSalva = await db.query(
        'usuarios',
        columns: ['senha_hash', 'senha_salt'],
        where: 'id = ?',
        whereArgs: [dono.id],
      );
      expect(senhaSalva.single['senha_hash'], isNot('Senha@123'));
      expect(senhaSalva.single['senha_salt'], isNotEmpty);

      final restaurado = await acesso.restaurarSessao();
      expect(restaurado?.id, dono.id);
      await acesso.logout(dono.id);
      expect(await acesso.restaurarSessao(), isNull);

      final login = await acesso.login(
        codigoComercio: dono.codigoComercio,
        emailLogin: 'dono@studioflow.test',
        senha: 'Senha@123',
        permanecerConectado: false,
      );
      expect(login.id, dono.id);
      expect(await acesso.restaurarSessao(), isNull);
    });

    test('gerente e colaborador respeitam permissões definidas', () async {
      final dono = await _criarComercio(acesso);
      await acesso.salvarUsuario(
        ator: dono,
        nome: 'Gerente',
        telefone: '11911111111',
        emailLogin: 'gerente@studioflow.test',
        senha: 'Senha@456',
        funcao: FuncaoUsuario.gerente,
        ativo: true,
        permissoes: {
          ModuloPermissao.agenda,
          ModuloPermissao.financeiro,
          ModuloPermissao.relatorios,
        },
      );
      await acesso.salvarUsuario(
        ator: dono,
        nome: 'Colaborador',
        telefone: '11922222222',
        emailLogin: 'colaborador@studioflow.test',
        senha: 'Senha@789',
        funcao: FuncaoUsuario.colaborador,
        ativo: true,
        permissoes: {ModuloPermissao.agenda},
      );

      final usuarios = await acesso.listarUsuarios(dono.comercioId);
      expect(
        usuarios.map((item) => item.funcao),
        containsAll([
          FuncaoUsuario.dono,
          FuncaoUsuario.gerente,
          FuncaoUsuario.colaborador,
        ]),
      );
      final gerente = await acesso.login(
        codigoComercio: dono.codigoComercio,
        emailLogin: 'gerente@studioflow.test',
        senha: 'Senha@456',
        permanecerConectado: false,
      );
      expect(gerente.pode(ModuloPermissao.financeiro), isTrue);
      expect(gerente.pode(ModuloPermissao.estoque), isFalse);
      final colaborador = await acesso.login(
        codigoComercio: dono.codigoComercio,
        emailLogin: 'colaborador@studioflow.test',
        senha: 'Senha@789',
        permanecerConectado: false,
      );
      expect(colaborador.pode(ModuloPermissao.agenda), isTrue);
      expect(colaborador.pode(ModuloPermissao.financeiro), isFalse);
    });

    test('configurações permanecem salvas', () async {
      final dono = await _criarComercio(acesso);
      const esperado = ConfiguracaoComercio(
        comercioId: '',
        nomeComercio: 'Studio atualizado',
        nomeExibicao: 'Studio Teste',
        telefone: '1133333333',
        whatsapp: '11999990000',
        endereco: 'Rua dos Testes, 2',
        chavePix: 'pix@teste.local',
        horarioAbertura: '09:00',
        horarioFechamento: '19:00',
        diasFuncionamento: {1, 2, 3, 4, 5},
        duracaoPadraoMinutos: 45,
        notificacoesAtivas: false,
        confirmarExclusoes: true,
      );
      await configuracoes.salvar(
        ConfiguracaoComercio(
          comercioId: dono.comercioId,
          nomeComercio: esperado.nomeComercio,
          nomeExibicao: esperado.nomeExibicao,
          telefone: esperado.telefone,
          whatsapp: esperado.whatsapp,
          endereco: esperado.endereco,
          chavePix: esperado.chavePix,
          horarioAbertura: esperado.horarioAbertura,
          horarioFechamento: esperado.horarioFechamento,
          diasFuncionamento: esperado.diasFuncionamento,
          duracaoPadraoMinutos: esperado.duracaoPadraoMinutos,
          notificacoesAtivas: esperado.notificacoesAtivas,
          confirmarExclusoes: esperado.confirmarExclusoes,
        ),
      );

      final carregado = await ConfiguracoesRepository(
        databaseProvider: () async => db,
      ).carregar(dono.comercioId);
      expect(carregado.nomeExibicao, 'Studio Teste');
      expect(carregado.diasFuncionamento, {1, 2, 3, 4, 5});
      expect(carregado.duracaoPadraoMinutos, 45);
      expect(carregado.notificacoesAtivas, isFalse);
    });

    test('IA local usa dados reais do SQLite', () async {
      final dono = await _criarComercio(acesso);
      final agora = DateTime(2026, 7, 13, 10);
      await db.insert('clientes', {
        'id': 'cli_ia',
        'nome': 'Cliente IA',
        'whatsapp': '11900000000',
        'data_cadastro': DateTime(2025).toIso8601String(),
        'comercio_id': dono.comercioId,
      });
      await db.insert('profissionais', {
        'id': 'pro_ia',
        'nome': 'Profissional IA',
        'whatsapp': '11900000001',
        'cargo': 'Colaborador',
        'data_cadastro': agora.toIso8601String(),
        'comercio_id': dono.comercioId,
      });
      await db.insert('servicos', {
        'id': 'ser_ia',
        'nome': 'Corte IA',
        'categoria': 'Cabelo',
        'preco': 100,
        'duracao_minutos': 60,
        'data_cadastro': agora.toIso8601String(),
        'comercio_id': dono.comercioId,
      });
      await db.insert('agendamentos', {
        'id': 'age_ia',
        'cliente_id': 'cli_ia',
        'profissional_id': 'pro_ia',
        'servico_id': 'ser_ia',
        'inicio': DateTime(2026, 7, 13, 14).toIso8601String(),
        'fim': DateTime(2026, 7, 13, 15).toIso8601String(),
        'valor_servico': 100,
        'data_criacao': agora.toIso8601String(),
        'comercio_id': dono.comercioId,
      });
      await db.insert('movimentacoes_financeiras', {
        'id': 'fin_ia',
        'tipo': 'entrada',
        'descricao': 'Recebimento IA',
        'valor': 100,
        'status': 'pago',
        'data': agora.toIso8601String(),
        'data_criacao': agora.toIso8601String(),
        'comercio_id': dono.comercioId,
      });
      final ia = IaLocalService(
        databaseProvider: () async => db,
        configuracoes: configuracoes,
      );
      final resumo = await ia.gerarResumo(dono.comercioId, agora: agora);

      expect(resumo.clientes, 1);
      expect(resumo.agendamentosHoje, 1);
      expect(resumo.servicoMaisFrequente, 'Corte IA');
      expect(resumo.recebidoMes, 100);
      expect(
        ia.responder('Como está minha agenda hoje?', resumo),
        contains('1'),
      );
    });
  });
}

Future<UsuarioAcesso> _criarComercio(AcessoRepository acesso) {
  return acesso.cadastrarComercio(
    const CadastroComercioEntrada(
      nomeComercio: 'Studio Teste',
      nomeExibicao: 'Studio Teste',
      responsavel: 'Pessoa Dona',
      telefone: '11999999999',
      email: 'dono@studioflow.test',
      senha: 'Senha@123',
      permanecerConectado: true,
    ),
  );
}
