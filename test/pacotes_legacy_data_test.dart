import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/repositories/pacotes_repository.dart';
import 'package:studioflow/repositories/acesso_repository.dart';
import 'package:studioflow/models/domain/acesso.dart';

void main() {
  late Database db;
  late String comercioId;

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
  });

  test('Identificar qual campo causa o erro String -> int', () async {
    await db.insert('clientes', {
      'id': 'cli_1',
      'comercio_id': comercioId,
      'nome': 'Cliente Maria',
      'whatsapp': '11999999999',
      'ativo': 1,
      'data_cadastro': DateTime.now().toIso8601String(),
    });

    await db.execute('DROP TABLE IF EXISTS sessoes_pacotes');
    await db.execute('DROP TABLE IF EXISTS pacotes_vendidos');

    await db.execute('''
      CREATE TABLE pacotes_vendidos (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        pacote_id TEXT NOT NULL,
        cliente_id TEXT NOT NULL,
        data_venda TEXT NOT NULL,
        valor_original TEXT,
        desconto TEXT,
        valor_final TEXT,
        forma_pagamento TEXT,
        status TEXT,
        validade_inicio TEXT,
        validade_fim TEXT,
        quantidade_sessoes TEXT,
        sessoes_utilizadas TEXT,
        sessoes_restantes TEXT,
        observacoes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        created_by TEXT,
        updated_by TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE sessoes_pacotes (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        pacote_vendido_id TEXT NOT NULL,
        ordem TEXT,
        servico_id_previsto TEXT,
        servico_id_realizado TEXT,
        data_agendada TEXT,
        horario_inicio TEXT,
        horario_fim TEXT,
        profissional_id TEXT,
        agendamento_id TEXT,
        unidade_id TEXT,
        sala_id TEXT,
        equipamento_id TEXT,
        status TEXT,
        valor_atribuido TEXT,
        observacoes TEXT,
        estoque_consumido TEXT,
        estoque_consumido_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        created_by TEXT,
        updated_by TEXT
      )
    ''');

    await db.insert('servicos', {
      'id': 'serv_1',
      'nome': 'Servico 1',
      'categoria': 'Cat 1',
      'preco': 100.0,
      'duracao_minutos': 30,
      'data_cadastro': DateTime.now().toIso8601String(),
    });

    await db.insert('pacotes', {
      'id': 'pct_1',
      'business_id': comercioId,
      'nome': 'Pacote String',
      'preco': '150.0', // double como string
      'validade_dias': '30', // int como string
      'regras_uso': '',
      'status': '1', // int como string
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    await db.insert('pacotes_vendidos', {
      'id': 'vda_1',
      'business_id': comercioId,
      'pacote_id': 'pct_1',
      'cliente_id': 'cli_1',
      'data_venda': DateTime.now().toIso8601String(),
      'valor_original': '150.0', // double como string
      'valor_final': '150.0', // double como string
      'quantidade_sessoes': '4', // int como string
      'sessoes_restantes': '4', // int como string
      'validade_fim': DateTime.now().add(Duration(days: 30)).toIso8601String(),
      'status': 'ativo',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    // Inserir algumas sessões com campos numéricos como string
    await db.insert('sessoes_pacotes', {
      'id': 'sess_1',
      'business_id': comercioId,
      'pacote_vendido_id': 'vda_1',
      'servico_id_previsto': 'serv_1',
      'ordem': '1', // int como string
      'status': 'disponivel',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    final repo = PacotesRepository(
      comercioId: comercioId,
      databaseProvider: () async => db,
    );

    final vendidos = await repo.listarVendas();
    expect(vendidos, isNotEmpty);
    expect(vendidos.length, 1);
  });
}
