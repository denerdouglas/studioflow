import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/models/domain/acesso.dart';
import 'package:studioflow/repositories/comanda_loja_repository.dart';
import 'package:studioflow/repositories/consignacao_repository.dart';
import 'package:studioflow/repositories/contas_receber_repository.dart';
import 'package:studioflow/services/ia_local_service.dart';
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
    await db.insert('clientes', {
      'id': 'client-1',
      'nome': 'Cliente',
      'whatsapp': '11999999999',
      'total_gasto': 0,
      'total_atendimentos': 0,
      'observacoes': '',
      'data_cadastro': now,
      'comercio_id': 'commerce-1',
      'ativo': 1,
    });
    await db.insert('estoque', {
      'id': 'product-1',
      'nome': 'Joia',
      'categoria': 'joias',
      'tipo': 'produto',
      'quantidade_atual': 10,
      'estoque_minimo': 2,
      'unidade': 'un',
      'preco_venda': 25,
      'codigo_barras': '7891',
      'estoque_destino': 'loja',
      'comercio_id': 'commerce-1',
      'ativo': 1,
      'data_cadastro': now,
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

  test('comanda finaliza, baixa estoque e cria conta a receber', () async {
    final repo = ComandaLojaRepository(databaseProvider: () async => db);
    final id = await repo.criar(clienteId: 'client-1');
    await repo.adicionarPorCodigo(id, '7891', quantidade: 2);
    await repo.finalizar(
      id,
      pagamentoInicial: 10,
      vencimento: DateTime.utc(2026, 8, 10),
    );

    expect((await db.query('pdv_vendas')).single['valor_total'], 50.0);
    expect((await db.query('estoque')).single['quantidade_atual'], 8.0);
    expect(
      (await db.query('contas_receber_loja')).single['valor_recebido'],
      10.0,
    );

    await repo.registrarPagamento(id, 40, 'pix');
    expect((await repo.listar()).single['status'], 'paga');
  });

  test('contas a receber calcula regra, parcial, total e estorno', () async {
    final commands = ComandaLojaRepository(databaseProvider: () async => db);
    final commandId = await commands.criar(clienteId: 'client-1');
    await commands.adicionarProduto(commandId, 'product-1', quantidade: 2);
    await commands.finalizar(commandId, vencimento: DateTime.utc(2026, 8, 10));
    final account = (await db.query('contas_receber_loja')).single;
    final receivables = ContasReceberRepository(
      databaseProvider: () async => db,
    );
    await receivables.registrarPagamento(account['id'] as String, 20, 'pix');
    expect(
      (await db.query('contas_receber_loja')).single['status'],
      'parcialmente_paga',
    );
    await receivables.registrarPagamento(account['id'] as String, 30, 'pix');
    expect((await db.query('contas_receber_loja')).single['status'], 'paga');
    final payments = await db.query(
      'contas_receber_pagamentos',
      orderBy: 'registrado_em',
    );
    await receivables.estornarPagamento(
      payments.last['id'] as String,
      'Pagamento devolvido',
    );
    expect(
      (await db.query('contas_receber_loja')).single['valor_recebido'],
      20.0,
    );
    expect(
      ContasReceberRepository.calcularVencimento(
        referencia: DateTime.utc(2026, 8, 3),
        tipo: 'ciclo_maleta',
        vencimentoDia: 5,
      ),
      DateTime.utc(2026, 10, 5),
    );
  });

  test('maleta usa código único e impede venda duplicada', () async {
    final repo = ConsignacaoRepository(databaseProvider: () async => db);
    final lotId = await repo.receberMaleta(
      fornecedorId: 'supplier-1',
      nomeLote: 'Maleta 08',
      pecas: const [
        {'codigo': 'JOIA-001', 'nome': 'Anel', 'preco': 100.0, 'repasse': 60.0},
      ],
    );
    final piece = (await repo.pecas(lotId)).single;
    await repo.venderPeca(piece['id'] as String, clienteId: 'client-1');
    expect(
      () => repo.venderPeca(piece['id'] as String, clienteId: 'client-1'),
      throwsStateError,
    );
    expect(
      (await repo.historicoMensal(
        DateTime.utc(2026, 8),
      )).where((event) => event['tipo'] == 'venda'),
      hasLength(1),
    );
  });
  test('IA interna consulta estoque real e persiste a conversa', () async {
    await db.update(
      'estoque',
      {'quantidade_atual': 1, 'estoque_minimo': 3},
      where: 'id = ?',
      whereArgs: ['product-1'],
    );
    final answer = await IaLocalService(
      databaseProvider: () async => db,
    ).conversar('Quais produtos estão acabando?', 'commerce-1');
    expect(answer, contains('Joia'));
    expect(answer, contains('reposição sugerida'));
    expect(await db.query('ia_mensagens'), hasLength(2));
    expect(
      (await db.query('ia_auditoria')).single['intencao'],
      'estoque_baixo',
    );
  });
  test('consignacao recebe e fecha lote devolvendo saldo', () async {
    final repo = ConsignacaoRepository(databaseProvider: () async => db);
    final id = await repo.receber(
      fornecedorId: 'supplier-1',
      produtoId: 'product-1',
      quantidade: 3,
      repasse: 10,
      precoVenda: 25,
      percentualSalao: 60,
      lote: 'Maleta agosto',
    );
    expect((await repo.resumo(id)).disponiveis, 3);
    await repo.fechar(id);
    expect((await db.query('estoque')).single['quantidade_atual'], 10.0);
    expect((await db.query('consignacoes')).single['status'], 'fechada');
  });
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
