import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/database/migrations/migration_v40.dart';
import 'package:studioflow/models/domain/acesso.dart';
import 'package:studioflow/repositories/acesso_repository.dart';
import 'package:studioflow/repositories/consignacao_acerto_repository.dart';
import 'package:studioflow/repositories/consignacao_conferencia_repository.dart';
import 'package:studioflow/repositories/consignacao_repository.dart';
import 'package:studioflow/services/session_controller.dart';

void main() {
  sqfliteFfiInit();

  test('V39 para V40 preserva remessa e peças e é idempotente', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute(
      'CREATE TABLE consignacoes (id TEXT PRIMARY KEY, comercio_id TEXT, status TEXT)',
    );
    await db.execute(
      'CREATE TABLE pecas_unicas (id TEXT PRIMARY KEY, comercio_id TEXT, lote_id TEXT)',
    );
    await db.execute(
      'CREATE TABLE movimentacoes_financeiras (id TEXT PRIMARY KEY)',
    );
    await db.insert('consignacoes', {
      'id': 'r1',
      'comercio_id': 'c1',
      'status': 'aberta',
    });
    await db.insert('pecas_unicas', {
      'id': 'p1',
      'comercio_id': 'c1',
      'lote_id': 'r1',
    });
    await MigrationV40.executar(db);
    await MigrationV40.executar(db);
    expect(await db.query('consignacoes'), hasLength(1));
    expect(await db.query('pecas_unicas'), hasLength(1));
    expect(
      (await db.query('consignacoes')).single['acerto_status'],
      'em_aberto',
    );
  });

  group('conferência física e acerto', () {
    late Database db;
    late UsuarioAcesso user;
    late String remessaId;
    late ConsignacaoConferenciaRepository conference;
    late ConsignacaoAcertoRepository settlement;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 40,
          onCreate: DatabaseSchemaLatest.criar,
        ),
      );
      user = await AcessoRepository(databaseProvider: () async => db)
          .cadastrarComercio(
            const CadastroComercioEntrada(
              nomeComercio: 'Consignação',
              nomeExibicao: 'Consignação',
              responsavel: 'Dona',
              telefone: '11999999999',
              email: 'consignacao@teste.local',
              senha: 'Senha@123',
              permanecerConectado: false,
            ),
          );
      SessionController.instance.entrar(user);
      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert('fornecedores', {
        'id': 'fornecedor_1',
        'comercio_id': user.comercioId,
        'nome': 'Fornecedor',
        'ativo': 1,
        'criado_em': now,
        'atualizado_em': now,
      });
      remessaId = await ConsignacaoRepository(databaseProvider: () async => db)
          .receberMaleta(
            fornecedorId: 'fornecedor_1',
            nomeLote: 'Remessa Bip',
            pecas: const [
              {
                'codigo': '527005',
                'nome': 'Colar',
                'preco': 100.0,
                'quantidade': 2,
              },
              {
                'codigo': 'OUTRO',
                'nome': 'Anel',
                'preco': 50.0,
                'quantidade': 1,
              },
            ],
          );
      conference = ConsignacaoConferenciaRepository(
        databaseProvider: () async => db,
        comercioId: user.comercioId,
        usuarioId: user.id,
      );
      settlement = ConsignacaoAcertoRepository(
        databaseProvider: () async => db,
        comercioId: user.comercioId,
        usuarioId: user.id,
      );
    });

    tearDown(() => db.close());

    test(
      'código repetido exige uma ocorrência e contador pode ser retomado',
      () async {
        final id = await conference.iniciar(
          remessaId: remessaId,
          finalidade: 'inventario',
        );
        final resolve = await conference.resolverCodigo(id, '527005');
        expect(resolve.state, ConsignacaoResolveState.multiplas);
        expect(resolve.multiplasOpcoes, hasLength(2));
        final pieceId = resolve.multiplasOpcoes.first['id'] as String;
        expect(
          await conference.conferirPeca(
            conferenciaId: id,
            pecaId: pieceId,
            leituraOriginal: '527005',
          ),
          isTrue,
        );
        expect(
          await conference.conferirPeca(
            conferenciaId: id,
            pecaId: pieceId,
            leituraOriginal: '527005',
          ),
          isFalse,
        );
        await conference.pausar(id);
        final resumed = await conference.iniciar(
          remessaId: remessaId,
          finalidade: 'inventario',
        );
        expect(resumed, id);
        final state = await conference.carregar(id);
        expect(state['conferido'], 1);
        expect(state['pendente'], 2);
        expect((await conference.resolverCodigo(id, '527005')).state, ConsignacaoResolveState.encontrada);
      },
    );

    test(
      'acerto calcula campos, exige divergência e pagamento é idempotente',
      () async {
        final pieces = await db.query(
          'pecas_unicas',
          where: 'lote_id=?',
          whereArgs: [remessaId],
        );
        final sold = pieces.first;
        await db.update(
          'pecas_unicas',
          {'status': 'vendida'},
          where: 'id=?',
          whereArgs: [sold['id']],
        );
        await db.insert('consignacao_eventos', {
          'id': 'sale_event',
          'comercio_id': user.comercioId,
          'consignacao_id': remessaId,
          'peca_id': sold['id'],
          'tipo': 'venda',
          'quantidade': 1,
          'valor': 100,
          'criado_em': DateTime.now().toUtc().toIso8601String(),
        });
        expect(
          () => settlement.salvar(
            remessaId,
            const ConsignacaoAcertoInput(
              quantidadeFornecedor: 2,
              valorFornecedor: 90,
            ),
          ),
          throwsStateError,
        );
        final data = await settlement.salvar(
          remessaId,
          const ConsignacaoAcertoInput(
            quantidadeFornecedor: 2,
            valorFornecedor: 90,
            comissaoPercentual: 30,
            repasse: 60,
            desconto: 5,
            taxas: 4,
            perdasFinanceiras: 3,
            ajustes: -2,
            confirmarDivergencia: true,
          ),
        );
        expect(data['comissao_valor'], 30);
        expect(data['divergencia_quantidade'], 1);
        expect(data['divergencia_valor'], -10);
        expect(data['resultado_liquido'], 36);
        final id = data['id'] as String;
        await settlement.marcarConferido(id);
        await settlement.pagar(id);
        await settlement.pagar(id);
        final movements = await db.query(
          'movimentacoes_financeiras',
          where: 'entidade_origem=? AND entidade_origem_id=?',
          whereArgs: ['consignacao_acerto', id],
        );
        expect(movements, hasLength(1));
        expect(movements.single['centro_resultado'], 'loja');
        expect(movements.single['tipo'], 'saida');
        await settlement.fechar(id);
        await settlement.reabrir(id);
        await settlement.marcarConferido(id);
        await settlement.pagar(id);
        expect(
          await db.query(
            'movimentacoes_financeiras',
            where: 'entidade_origem_id=?',
            whereArgs: [id],
          ),
          hasLength(1),
        );
      },
    );
  });
}
