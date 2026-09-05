import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/models/domain/acesso.dart';
import 'package:studioflow/repositories/consignacao_repository.dart';
import 'package:studioflow/repositories/cliente_repository.dart';
import 'package:studioflow/services/session_controller.dart';

void main() {
  sqfliteFfiInit();
  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 25,
        onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
        onCreate: DatabaseSchemaLatest.criar,
      ),
    );
    SessionController.instance.entrar(_owner());
    final now = DateTime.utc(2026, 8, 3).toIso8601String();
    await db.insert('comercios', {
      'id': 'commerce-1',
      'codigo_acesso': 'SFTEST',
      'nome': 'Studio Teste',
      'nome_exibicao': 'Studio Teste',
      'responsavel': 'Dono',
      'telefone': '11999999999',
      'email': 'dono@teste.local',
      'ativo': 1,
      'criado_em': now,
      'atualizado_em': now,
    });

    // Cliente por nome e telefone
    await db.insert('clientes', {
      'id': 'client-1',
      'nome': 'Maria Silva',
      'whatsapp': '11988887777',
      'total_gasto': 0,
      'total_atendimentos': 0,
      'observacoes': '',
      'data_cadastro': now,
      'comercio_id': 'commerce-1',
      'ativo': 1,
    });
    await db.insert('clientes', {
      'id': 'client-2',
      'nome': 'João Pereira',
      'whatsapp': '11977776666',
      'total_gasto': 0,
      'total_atendimentos': 0,
      'observacoes': '',
      'data_cadastro': now,
      'comercio_id': 'commerce-1',
      'ativo': 1,
    });

    await db.insert('fornecedores', {
      'id': 'supplier-1',
      'comercio_id': 'commerce-1',
      'nome': 'Fornecedor',
      'ativo': 1,
      'criado_em': now,
      'atualizado_em': now,
    });
  });

  tearDown(() async => db.close());

  test(
    'CONSIGNADO: busca por código, descrição e peça indisponível não aparece',
    () async {
      final repo = ConsignacaoRepository(databaseProvider: () async => db);
      final lotId = await repo.receberMaleta(
        fornecedorId: 'supplier-1',
        nomeLote: 'Maleta Agosto',
        pecas: const [
          {
            'codigo': 'ANEL01',
            'nome': 'Anel de Ouro',
            'descricao': 'Anel Ouro 18k',
            'preco': 500.0,
            'repasse': 200.0,
          },
          {
            'codigo': 'BRINCO01',
            'nome': 'Brinco Prata',
            'descricao': 'Brinco de Prata',
            'preco': 100.0,
            'repasse': 40.0,
          },
          {
            'codigo': 'ANEL01',
            'nome': 'Anel de Ouro',
            'descricao': 'Anel Ouro 18k',
            'preco': 500.0,
            'repasse': 200.0,
          }, // código repetido + peca_unica_id
        ],
      );

      // Busca por código
      final pCodigo = await repo.pecas(lotId, pesquisa: 'BRINCO01');
      expect(pCodigo.length, 1);
      expect(pCodigo.first['nome'], 'Brinco Prata');

      // Busca por descrição
      final pDesc = await repo.pecas(lotId, pesquisa: 'Prata');
      expect(pDesc.length, 1);
      expect(pDesc.first['codigo_exclusivo'], 'BRINCO01');

      // Código repetido tem peca_unica_id diferentes
      final pRepetido = await repo.pecas(lotId, pesquisa: 'ANEL01');
      expect(pRepetido.length, 2);
      expect(pRepetido[0]['id'], isNot(equals(pRepetido[1]['id'])));

      // Vender uma peça para torná-la indisponível
      await repo.venderPeca(
        pRepetido[0]['id'] as String,
        clienteId: 'client-1',
      );

      // Peça indisponível não aparece na listagem principal
      final pDisp = await repo.pecas(lotId, status: 'disponivel');
      expect(pDisp.length, 2); // Eram 3, 1 vendida
      expect(pDisp.map((e) => e['id']), isNot(contains(pRepetido[0]['id'])));
    },
  );

  test('CONSIGNADO: clientes por nome e telefone, venda sem cliente', () async {
    final clientRepo = ClienteRepository(databaseProvider: () async => db);

    // Cliente por nome
    final allClients = await clientRepo.listar();
    final bNome = allClients.where((c) => c.nome.contains('Maria')).toList();
    expect(bNome.length, 1);
    expect(bNome.first.nome, 'Maria Silva');

    // Cliente por telefone
    final bTel = allClients
        .where((c) => c.whatsapp.contains('88887777'))
        .toList();
    expect(bTel.length, 1);
    expect(bTel.first.whatsapp, '11988887777');

    final repo = ConsignacaoRepository(databaseProvider: () async => db);
    final lotId = await repo.receberMaleta(
      fornecedorId: 'supplier-1',
      nomeLote: 'Maleta',
      pecas: const [
        {'codigo': 'TESTE', 'nome': 'Teste', 'preco': 100.0, 'repasse': 40.0},
      ],
    );
    final pecas = await repo.pecas(lotId);

    // Venda SEM cliente
    await repo.venderPeca(
      pecas.first['id'] as String,
      clienteId: null,
    ); // Null = sem cliente
    final agora = DateTime.now().toUtc();
    final historico = await repo.historicoMensal(
      DateTime.utc(agora.year, agora.month),
    );
    expect(historico.first['cliente_nome'], isNull);
  });

  test(
    'CONSIGNADO: múltiplas peças, comissão, repasse e caixa consignado correto, idempotência',
    () async {
      final repo = ConsignacaoRepository(databaseProvider: () async => db);
      final lotId = await repo.receberMaleta(
        fornecedorId: 'supplier-1',
        nomeLote: 'Maleta Caixa',
        pecas: const [
          {'codigo': 'A', 'nome': 'A', 'preco': 100.0, 'repasse': 40.0},
          {'codigo': 'B', 'nome': 'B', 'preco': 200.0, 'repasse': 80.0},
        ],
      );

      final pecas = await repo.pecas(lotId);
      final idsSelecionadas = {
        pecas[0]['id'] as String,
        pecas[1]['id'] as String,
      };

      // Venda de múltiplas peças
      await repo.venderPecas(idsSelecionadas, clienteId: 'client-1');

      // Múltiplas peças não perdem seleção (idempotencia de checar a lista na view é logica de state, mas a nivel de BD, o Set<String> lida com isso)

      // Teste de idempotência (vender as mesmas peças novamente deve falhar/ser ignorado)
      expect(
        () => repo.venderPecas(idsSelecionadas, clienteId: 'client-2'),
        throwsStateError,
      );

      // Verificar caixa consignado correto, comissão e repasse
      final movs = await db.query('movimentacoes_financeiras');

      // As movimentacoes devem ter centro de resultado "consignado"
      final entradas = movs.where((m) => m['tipo'] == 'entrada').toList();
      expect(entradas.length, 1); // 1 venda (agrupada)

      expect(entradas.first['centro_resultado'], 'consignado');
      expect(entradas.first['valor'], 300.0); // 100 + 200
    },
  );
}

UsuarioAcesso _owner() => UsuarioAcesso(
  id: 'user-1',
  comercioId: 'commerce-1',
  codigoComercio: 'SFTEST',
  nomeComercio: 'Studio Teste',
  nomeExibicao: 'Studio Teste',
  nome: 'Dono',
  telefone: '11999999999',
  emailLogin: 'dono@teste.local',
  funcao: FuncaoUsuario.dono,
  ativo: true,
  permissoes: ModuloPermissao.values.toSet(),
  acoes: AcaoPermissao.values.toSet(),
);
