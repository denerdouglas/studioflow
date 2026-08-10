import 'package:flutter_test/flutter_test.dart';
import 'package:studioflow/models/domain/pacote_servico.dart';
import 'package:studioflow/repositories/pacotes_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_schema_latest.dart';


import 'package:studioflow/repositories/acesso_repository.dart';
import 'package:studioflow/models/domain/acesso.dart';

void main() {
  late PacotesRepository repository;
  late Database db;
  late String comercioId;
  late String usuarioId;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: DatabaseSchemaLatest.criar,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
      ),
    );

    final acesso = AcessoRepository(databaseProvider: () async => db);
    final owner = await acesso.cadastrarComercio(
      const CadastroComercioEntrada(
        nomeComercio: 'Studio Teste',
        nomeExibicao: 'Studio Teste',
        responsavel: 'Dono',
        telefone: '11999999999',
        email: 'test@test.com',
        senha: 'Senha@123456',
        permanecerConectado: false,
      ),
    );
    comercioId = owner.comercioId;
    usuarioId = owner.id;

    await db.insert('clientes', {
      'id': 'cliente_1',
      'comercio_id': comercioId,
      'nome': 'Cliente Maria',
      'whatsapp': '11999999999',
      'ativo': 1,
      'data_cadastro': DateTime.now().toIso8601String(),
    });

    await db.insert('profissionais', {
      'id': 'prof_1',
      'comercio_id': comercioId,
      'nome': 'Profissional Joana',
      'whatsapp': '11988888888',
      'cargo': 'Cabelereira',
      'ativo': 1,
      'data_cadastro': DateTime.now().toIso8601String(),
    });

    await db.insert('servicos', {
      'id': 'srv_1',
      'business_id': comercioId,
      'nome': 'Corte',
      'categoria': 'Cabelo',
      'preco': 50.0,
      'duracao_minutos': 30,
      'ativo': 1,
      'data_cadastro': DateTime.now().toIso8601String(),
    });

    await db.insert('servicos', {
      'id': 'srv_2',
      'business_id': comercioId,
      'nome': 'Escova',
      'categoria': 'Cabelo',
      'preco': 40.0,
      'duracao_minutos': 40,
      'ativo': 1,
      'data_cadastro': DateTime.now().toIso8601String(),
    });

    repository = PacotesRepository(
      databaseProvider: () async => db,
      comercioId: comercioId,
      usuarioId: usuarioId,
    );
  });

  test('Fluxo completo: Criar pacote, listar, vender e listar sessoes', () async {
    // 1. Criar pacote
    final pacoteId = await repository.salvarModelo(
      PacoteEntrada(
        nome: 'Pacote Teste',
        categoria: 'Geral',
        precoPacote: 150.0,
        validadeDias: 30,
        itens: [
          PacoteItemEntrada(servicoId: 'srv_1', quantidade: 2),
          PacoteItemEntrada(servicoId: 'srv_2', quantidade: 1),
        ],
      ),
    );
    expect(pacoteId, isNotEmpty);

    // 2. Listar modelos garantindo tipos corretos (não causar crash de null/tipo)
    final modelos = await repository.listarModelos();
    expect(modelos.length, 1);
    expect(modelos.first.nome, 'Pacote Teste');
    expect(modelos.first.preco, 150.0);
    expect(modelos.first.totalSessoes, 3); // 2 + 1

    // 3. Venda do pacote congelando snapshot
    final vendaId = await repository.vender(
      VendaPacoteEntrada(
        pacoteId: pacoteId,
        clienteId: 'cliente_1',
        vendedorProfissionalId: 'prof_1',
        formaPagamento: 'Pix',
        dataCompra: DateTime.now(),
      ),
    );
    expect(vendaId, isNotEmpty);

    // 4. Listar sessoes disponíveis do cliente
    final sessoes = await repository.listarSessoesDisponiveisCliente(
      'cliente_1',
    );
    expect(sessoes.length, 3);

    final cortes = sessoes.where((s) => s.servicoId == 'srv_1').length;
    final escovas = sessoes.where((s) => s.servicoId == 'srv_2').length;

    expect(cortes, 2);
    expect(escovas, 1);
  });
}
