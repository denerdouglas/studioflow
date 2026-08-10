import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/models/domain/acesso.dart';
import 'package:studioflow/repositories/acesso_repository.dart';
import 'package:studioflow/repositories/cliente_repository.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/services/session_controller.dart';

void main() {
  late Database db;
  late ClienteRepository repository;
  late AcessoRepository acesso;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: DatabaseSchemaLatest.criar,
      ),
    );

    acesso = AcessoRepository(databaseProvider: () async => db);
    final dono = await acesso.cadastrarComercio(
      const CadastroComercioEntrada(
        nomeComercio: 'Loja',
        nomeExibicao: 'Loja',
        responsavel: 'Admin',
        email: 'admin@loja.com',
        telefone: '11999999999',
        senha: 'password123',
        permanecerConectado: true,
      ),
    );

    SessionController.instance.entrar(dono);

    repository = ClienteRepository(databaseProvider: () async => db);
  });

  tearDown(() async {
    await db.close();
  });

  test('Deve buscar corretamente ignorando maiúsculas e minúsculas', () async {
    await repository.inserir(
      ClienteRegistro(
        id: '1',
        nome: 'José da Silva',
        whatsapp: '11999999999',
        profissional: 'Ana',
        ultimoServico: '',
        totalGasto: 0,
        totalAtendimentos: 0,
        observacoes: '',
        dataCadastro: DateTime.now(),
      ),
    );

    final resultados = await repository.buscarPesquisando('josé');
    expect(resultados, hasLength(1));
    expect(resultados.first.nome, 'José da Silva');

    final resultadosUpper = await repository.buscarPesquisando('JOSÉ');
    expect(resultadosUpper, hasLength(1));
  });

  test('Deve buscar corretamente ignorando acentos', () async {
    await repository.inserir(
      ClienteRegistro(
        id: '2',
        nome: 'Márcia Conceição',
        whatsapp: '11888888888',
        profissional: 'Ana',
        ultimoServico: '',
        totalGasto: 0,
        totalAtendimentos: 0,
        observacoes: '',
        dataCadastro: DateTime.now(),
      ),
    );

    final resultados = await repository.buscarPesquisando('marcia conceicao');
    expect(resultados, hasLength(1));
    expect(resultados.first.nome, 'Márcia Conceição');
  });

  test('Deve encontrar por número de telefone/whatsapp', () async {
    await repository.inserir(
      ClienteRegistro(
        id: '3',
        nome: 'Cliente Telefone',
        whatsapp: '11977776666',
        telefone: '1144443333',
        profissional: 'Ana',
        ultimoServico: '',
        totalGasto: 0,
        totalAtendimentos: 0,
        observacoes: '',
        dataCadastro: DateTime.now(),
      ),
    );

    final resultWhats = await repository.buscarPesquisando('97777');
    expect(resultWhats, hasLength(1));

    final resultTel = await repository.buscarPesquisando('44443');
    expect(resultTel, hasLength(1));
  });

  test('Stress Test: Busca paginada em 10.000 clientes', () async {
    // Inserção em batch para ser mais rápido
    final batch = db.batch();
    for (int i = 0; i < 10000; i++) {
      String nome = 'Cliente $i';
      if (i == 5000) nome = 'Maria João Especial';
      if (i == 5001) nome = 'Mária (com acento)';

      batch.insert('clientes', {
        'id': 'c_$i',
        'nome': nome,
        'whatsapp': '1190000$i',
        'telefone': '',
        'email': '',
        'profissional_principal_id': 'prof_1',
        'observacoes': '',
        'ativo': 1,
        'data_cadastro': DateTime.now().toIso8601String(),
        'total_atendimentos': 0,
        'total_gasto': 0,
        'consentimento_whatsapp': 0,
        'consentimento_marketing': 0,
        'atualizado_em': DateTime.now().toIso8601String(),
        'comercio_id': SessionController.instance.usuario!.comercioId,
      });
    }
    await batch.commit(noResult: true);

    final inicio = DateTime.now();

    // Busca normal paginada sem termo (só listagem)
    final listagem = await repository.buscarPesquisando(
      '',
      limit: 20,
      offset: 0,
    );
    expect(listagem, hasLength(20));

    // Busca com acento (LOWER + REPLACE dinâmico) em 10k registros
    final pesquisaAcento = await repository.buscarPesquisando(
      'maria',
      limit: 10,
      offset: 0,
    );

    final duracao = DateTime.now().difference(inicio).inMilliseconds;

    // O ideal é que o banco resolva em menos de 100ms
    expect(duracao, lessThan(300));

    // A pesquisa por maria tem que retornar os 2 especiais criados + os "Cliente maria" se houvesse,
    // mas não há nenhum, pois chamamos os outros de Cliente $i.
    // Então deve retornar 2.
    expect(pesquisaAcento, hasLength(2));

    final nomes = pesquisaAcento.map((c) => c.nome).toList();
    expect(nomes.contains('Maria João Especial'), isTrue);
    expect(nomes.contains('Mária (com acento)'), isTrue);
  });
}
