import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/models/domain/acesso.dart';
import 'package:studioflow/repositories/cliente_repository.dart';
import 'package:studioflow/services/session_controller.dart';

void main() {
  sqfliteFfiInit();

  group('edição e exclusão de clientes', () {
    late Database db;
    late ClienteRepository repository;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 24,
          onConfigure: (database) =>
              database.execute('PRAGMA foreign_keys = ON'),
          onCreate: DatabaseSchemaLatest.criar,
        ),
      );
      SessionController.instance.entrar(_usuarioComClientes());
      repository = ClienteRepository(databaseProvider: () async => db);
    });

    tearDown(() async {
      await db.close();
    });

    test('edita contato criado e reflete imediatamente na consulta', () async {
      final original = _cliente('cliente-editar', '11911111111');
      await repository.inserir(original);

      await repository.atualizar(
        original.copiarCom(
          nome: 'Cliente Atualizada',
          whatsapp: '11922222222',
          email: 'atualizada@studioflow.test',
        ),
      );

      final atualizado = await repository.buscarPorId(original.id);
      expect(atualizado?.nome, 'Cliente Atualizada');
      expect(atualizado?.whatsapp, '11922222222');
      expect(atualizado?.email, 'atualizada@studioflow.test');
      expect((await repository.listar()).single.nome, 'Cliente Atualizada');
    });

    test('impede WhatsApp duplicado durante edição', () async {
      final primeiro = _cliente('cliente-1', '11911111111');
      final segundo = _cliente('cliente-2', '11922222222');
      await repository.inserir(primeiro);
      await repository.inserir(segundo);

      expect(
        () => repository.atualizar(
          segundo.copiarCom(whatsapp: primeiro.whatsapp),
        ),
        throwsStateError,
      );
    });

    test('exclusão é lógica e preserva histórico relacionado', () async {
      final cliente = _cliente('cliente-historico', '11933333333');
      await repository.inserir(cliente);
      final agora = DateTime.now().toUtc();
      await db.execute('PRAGMA foreign_keys = OFF');
      await db.insert('agendamentos', {
        'id': 'agenda-cliente',
        'cliente_id': cliente.id,
        'profissional_id': 'profissional-1',
        'servico_id': 'servico-1',
        'inicio': agora.toIso8601String(),
        'fim': agora.add(const Duration(hours: 1)).toIso8601String(),
        'status': 'confirmado',
        'valor_servico': 50.0,
        'observacoes': '',
        'confirmado': 1,
        'data_criacao': agora.toIso8601String(),
        'comercio_id': 'comercio-teste',
      });

      await repository.excluir(cliente.id);

      expect(await repository.buscarPorId(cliente.id), isNull);
      expect(await repository.listar(), isEmpty);
      final registro = await db.query(
        'clientes',
        where: 'id = ?',
        whereArgs: [cliente.id],
      );
      expect(registro.single['ativo'], 0);
      expect(
        await db.query(
          'agendamentos',
          where: 'cliente_id = ?',
          whereArgs: [cliente.id],
        ),
        hasLength(1),
      );
    });

    test('exclusão inexistente falha sem sucesso falso', () async {
      expect(() => repository.excluir('inexistente'), throwsStateError);
    });

    test('usuário sem módulo Clientes não altera nem exclui', () async {
      final cliente = _cliente('cliente-protegido', '11944444444');
      await repository.inserir(cliente);
      SessionController.instance.entrar(_usuarioSemClientes());

      expect(
        () => repository.atualizar(cliente.copiarCom(nome: 'Indevido')),
        throwsStateError,
      );
      expect(() => repository.excluir(cliente.id), throwsStateError);
      expect((await db.query('clientes')).single['ativo'], 1);
    });
  });
}

ClienteRegistro _cliente(String id, String whatsapp) => ClienteRegistro(
  id: id,
  nome: 'Cliente $id',
  whatsapp: whatsapp,
  profissional: 'Profissional',
  ultimoServico: 'Nenhum atendimento',
  totalGasto: 0,
  totalAtendimentos: 0,
  observacoes: '',
  dataCadastro: DateTime.utc(2026, 8, 3),
);

UsuarioAcesso _usuarioComClientes() => _usuario({ModuloPermissao.clientes});

UsuarioAcesso _usuarioSemClientes() => _usuario({ModuloPermissao.agenda});

UsuarioAcesso _usuario(Set<ModuloPermissao> permissoes) => UsuarioAcesso(
  id: 'usuario-teste',
  comercioId: 'comercio-teste',
  codigoComercio: 'SFTESTE',
  nomeComercio: 'Studio Teste',
  nomeExibicao: 'Studio Teste',
  nome: 'Usuário',
  telefone: '11999999999',
  emailLogin: 'usuario@studioflow.test',
  funcao: FuncaoUsuario.colaborador,
  ativo: true,
  permissoes: permissoes,
  acoes: const {},
);
