import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/models/domain/acesso.dart';
import 'package:studioflow/repositories/loja_repository.dart';
import 'package:studioflow/services/session_controller.dart';

void main() {
  late Database db;

  UsuarioAcesso owner() => UsuarioAcesso(
    id: 'user_owner',
    comercioId: 'biz_a',
    codigoComercio: 'BIZ',
    nomeComercio: 'Business',
    nomeExibicao: 'Owner',
    nome: 'Owner',
    telefone: '11999999999',
    emailLogin: 'owner@test.com',
    funcao: FuncaoUsuario.dono,
    ativo: true,
    permissoes: {},
    acoes: {},
  );

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 43,
        onCreate: DatabaseSchemaLatest.criar,
      ),
    );
    SessionController.instance.entrar(owner());
  });

  test('ResoluÃ§Ã£o forte nÃ£o usa nome para encontrar produto', () async {
    // Insere dois produtos
    await db.insert('estoque', {
      'id': 'prod_a',
      'comercio_id': 'biz_a',
      'nome': 'Shampoo X',
      'codigo_interno': 'COD123',
      'codigo_barras': '78910',
      'tipo_produto': 'venda',
      'categoria': 'Cabelo',
      'tipo': 'Produto',
      'unidade': 'UN',
      'conteudo_por_unidade': 1.0,
      'unidade_conteudo': 'UN',
      'preco_venda': 100,
      'custo_unitario': 50,
      'data_cadastro': DateTime.now().toIso8601String(),
      'atualizado_em': DateTime.now().toIso8601String(),
      'quantidade_atual': 10,
    });

    await db.insert('estoque', {
      'id': 'prod_b',
      'comercio_id': 'biz_a',
      'nome': 'Shampoo X', // Nome duplicado
      'codigo_interno': 'COD999',
      'codigo_barras': '78999',
      'tipo_produto': 'venda',
      'categoria': 'Cabelo',
      'tipo': 'Produto',
      'unidade': 'UN',
      'conteudo_por_unidade': 1.0,
      'unidade_conteudo': 'UN',
      'preco_venda': 150,
      'custo_unitario': 70,
      'data_cadastro': DateTime.now().toIso8601String(),
      'atualizado_em': DateTime.now().toIso8601String(),
      'quantidade_atual': 5,
    });

    final repo = LojaRepository(databaseProvider: () async => db);

    // 1. Busca textual encontra ambos
    final itensTextuais = await repo.listarItensParaVenda(
      pesquisa: 'Shampoo X',
    );
    expect(itensTextuais.length, 2);

    // 2. ResoluÃ§Ã£o forte nÃ£o encontra por nome (agora que removemos OR e.nome = ?)
    final resolvedPorNome = await repo.buscarCodigo('Shampoo X');
    expect(resolvedPorNome, isNull);

    // 3. ResoluÃ§Ã£o forte encontra por ID
    final resolvedPorId = await repo.buscarCodigo('prod_a');
    expect(resolvedPorId, isNotNull);
    expect(resolvedPorId!.id, 'prod_a');

    // 4. ResoluÃ§Ã£o forte encontra por cÃ³digo de barras
    final resolvedPorGTIN = await repo.buscarCodigo('78910');
    expect(resolvedPorGTIN, isNotNull);
    expect(resolvedPorGTIN!.id, 'prod_a');

    // 5. ResoluÃ§Ã£o forte encontra por cÃ³digo interno
    final resolvedPorInterno = await repo.buscarCodigo('COD999');
    expect(resolvedPorInterno, isNotNull);
    expect(resolvedPorInterno!.id, 'prod_b');
  });

  tearDown(() async {
    await db.close();
  });
}
