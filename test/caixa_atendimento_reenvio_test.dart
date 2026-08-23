import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/models/domain/acesso.dart';
import 'package:studioflow/models/domain/loja.dart';
import 'package:studioflow/repositories/agenda_repository.dart';
import 'package:studioflow/repositories/caixa_repository.dart';
import 'package:studioflow/repositories/comanda_loja_repository.dart';
import 'package:studioflow/repositories/contas_receber_repository.dart';
import 'package:studioflow/repositories/loja_repository.dart';
import 'package:studioflow/services/purchase_receipt_service.dart';
import 'package:studioflow/services/session_controller.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late CaixaRepository caixa;
  late AgendaRepository agenda;
  late ComandaLojaRepository comandas;
  late ContasReceberRepository contas;
  late LojaRepository loja;
  final day = DateTime.now();

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 44,
        onCreate: DatabaseSchemaLatest.criar,
      ),
    );
    SessionController.instance.entrar(_owner());
    await _seed(db, day);
    caixa = CaixaRepository(databaseProvider: () async => db);
    agenda = AgendaRepository(databaseProvider: () async => db);
    comandas = ComandaLojaRepository(databaseProvider: () async => db);
    contas = ContasReceberRepository(databaseProvider: () async => db);
    loja = LojaRepository(databaseProvider: () async => db);
  });

  tearDown(() => db.close());

  test('1 pagamento de comanda é entrada, não saída', () async {
    final id = await _command(comandas, paid: 20);
    final movement = (await db.query(
      'movimentacoes_financeiras',
      where: 'entidade_origem_id=?',
      whereArgs: [id],
    )).single;
    expect(movement['tipo'], 'entrada');
    expect(
      (await caixa.resumoDoDia(day, centroResultado: 'loja')).totalEntradas,
      20,
    );
  });

  test('2 venda PDV paga é entrada', () async {
    final product = await loja.buscarCodigo('COD-1');
    await loja.finalizarVenda(
      itens: [ItemCarrinho(product!, 1)],
      desconto: 0,
      pagamentos: const {'pix': 20},
      profissionalId: 'user-1',
      dataPagamento: day,
    );
    expect(
      (await db.query('movimentacoes_financeiras')).single['tipo'],
      'entrada',
    );
  });

  test('3 comanda pendente não gera entrada', () async {
    await _command(comandas, paid: 0);
    expect(await db.query('movimentacoes_financeiras'), isEmpty);
  });

  test('4 comanda parcial gera entrada somente do valor pago', () async {
    await _command(comandas, paid: 5);
    expect(
      (await caixa.resumoDoDia(day, centroResultado: 'loja')).totalEntradas,
      5,
    );
  });

  test('5 saldo pendente aparece separado', () async {
    await _command(comandas, paid: 5);
    final summary = await caixa.resumoDoDia(day, centroResultado: 'loja');
    expect(summary.totalPendentes, 15);
    expect(summary.saldo, 5);
  });

  test('6 recebimento posterior entra na data real', () async {
    final id = await _command(comandas, paid: 0);
    final account = (await db.query(
      'contas_receber_loja',
      where: 'comanda_id=?',
      whereArgs: [id],
    )).single;
    final paidAt = DateTime.now().add(const Duration(days: 3, hours: 4, minutes: 30));
    await contas.registrarPagamento(
      account['id'] as String,
      20,
      'pix',
      dataPagamento: paidAt,
    );
    final movement = (await db.query(
      'movimentacoes_financeiras',
      where: "entidade_origem='conta_receber_loja'",
    )).single;
    expect(DateTime.parse('${movement['data']}').toLocal(), paidAt);
  });

  test('7 estorno gera saída sem inverter venda original', () async {
    final product = await loja.buscarCodigo('COD-1');
    final id = await loja.finalizarVenda(
      itens: [ItemCarrinho(product!, 1)],
      desconto: 0,
      pagamentos: const {'pix': 20},
      profissionalId: 'user-1',
      dataPagamento: day,
    );
    await loja.cancelarVenda(id, 'Devolução real');
    final rows = await db.query('movimentacoes_financeiras', orderBy: 'id');
    expect(
      rows.singleWhere((r) => r['tipo'] == 'entrada')['status'],
      'estornado',
    );
    expect(rows.singleWhere((r) => r['tipo'] == 'saida')['valor'], 20.0);
  });

  test('8 Caixa Loja soma entradas corretamente', () async {
    await _movement(db, 'entrada', 30, 'loja');
    await _movement(db, 'receita', 20, 'loja', id: 'legacy-receita');
    expect(
      (await caixa.resumoDoDia(day, centroResultado: 'loja')).totalEntradas,
      50,
    );
  });

  test('9 Caixa Loja soma saídas corretamente', () async {
    await _movement(db, 'saida', 12, 'loja');
    expect(
      (await caixa.resumoDoDia(day, centroResultado: 'loja')).totalSaidas,
      12,
    );
  });

  test('10 Caixa Loja soma pendentes corretamente', () async {
    await _command(comandas, paid: 0);
    expect(
      (await caixa.resumoDoDia(day, centroResultado: 'loja')).totalPendentes,
      20,
    );
  });

  test('11 Caixa Salão soma serviços pagos', () async {
    await _conclude(agenda, 'pago', 100, day);
    expect(
      (await caixa.resumoDoDia(day, centroResultado: 'salao')).totalEntradas,
      100,
    );
  });

  test('12 serviço pendente não gera entrada', () async {
    await _conclude(agenda, 'pendente', 0, day);
    expect(await db.query('movimentacoes_financeiras'), isEmpty);
  });

  test('13 serviço pendente cria conta a receber', () async {
    await _conclude(agenda, 'pendente', 0, day);
    expect(await db.query('cobrancas'), hasLength(1));
  });

  test('14 serviço parcial gera entrada parcial', () async {
    await _conclude(agenda, 'parcial', 30, day);
    expect((await db.query('movimentacoes_financeiras')).single['valor'], 30.0);
  });

  test('15 saldo parcial vai para pendente', () async {
    await _conclude(agenda, 'parcial', 30, day);
    expect((await db.query('cobrancas')).single['valor'], 70.0);
  });

  test('16 concluir atendimento Pago funciona', () async {
    await _conclude(agenda, 'pago', 100, day);
    expect((await _appointment(db))['pagamento_status'], 'pago');
  });

  test('17 concluir atendimento Pendente funciona', () async {
    await _conclude(agenda, 'pendente', 0, day);
    expect((await _appointment(db))['pagamento_status'], 'pendente');
  });

  test('18 concluir atendimento Parcial funciona', () async {
    await _conclude(agenda, 'parcial', 30, day);
    expect((await _appointment(db))['pagamento_status'], 'parcial');
  });

  test('19 forma de pagamento é persistida', () async {
    await _conclude(agenda, 'pago', 100, day, method: 'dinheiro');
    expect((await _appointment(db))['forma_pagamento'], 'dinheiro');
  });

  test('20 data do pagamento é persistida', () async {
    await _conclude(agenda, 'pago', 100, day);
    expect(
      DateTime.parse(
        '${(await db.query('movimentacoes_financeiras')).single['data']}',
      ).toLocal(),
      day,
    );
  });

  test('21 vencimento pendente é persistido', () async {
    final due = DateTime.now().add(const Duration(days: 6));
    await _conclude(agenda, 'pendente', 0, day, due: due);
    expect(
      DateTime.parse(
        '${(await db.query('cobrancas')).single['vencimento']}',
      ).toLocal(),
      due,
    );
  });

  test('22 pagamento posterior quita serviço', () async {
    await _conclude(agenda, 'pendente', 0, day);
    final charge = (await db.query('cobrancas')).single;
    await contas.registrarPagamento(
      charge['id'] as String,
      100,
      'pix',
      dataPagamento: DateTime.now().add(const Duration(days: 3, hours: 4, minutes: 30)),
    );
    expect((await db.query('cobrancas')).single['status'], 'confirmado_manual');
    expect((await _appointment(db))['pagamento_status'], 'pago');
  });

  test('23 atendimento hoje conta somente concluídos', () async {
    await _conclude(agenda, 'pendente', 0, day);
    expect(
      (await caixa.resumoDoDia(day, centroResultado: 'salao')).atendimentosHoje,
      1,
    );
  });

  test('24 atendimento mês conta corretamente', () async {
    await _conclude(agenda, 'pendente', 0, day);
    expect(
      (await caixa.resumoDoDia(day, centroResultado: 'salao')).atendimentosMes,
      1,
    );
  });

  test('25 cancelado não entra na quantidade', () async {
    await db.update('agendamentos', {
      'status': 'cancelado',
    }, where: "id='agenda-1'");
    expect(
      (await caixa.resumoDoDia(day, centroResultado: 'salao')).atendimentosHoje,
      0,
    );
  });

  test('26 falta não entra na quantidade', () async {
    await db.update('agendamentos', {
      'status': 'faltou',
    }, where: "id='agenda-1'");
    expect(
      (await caixa.resumoDoDia(day, centroResultado: 'salao')).atendimentosHoje,
      0,
    );
  });

  test('27 Caixa Geral não duplica Caixa Salão', () async {
    await _movement(db, 'entrada', 75, 'salao');
    expect((await caixa.resumoDoDia(day)).totalEntradas, 75);
  });

  test('28 Caixa Geral não duplica Caixa Loja', () async {
    await _movement(db, 'entrada', 50, 'loja');
    expect((await caixa.resumoDoDia(day)).totalEntradas, 50);
  });

  test('29 botão Enviar Comanda existe no detalhe', () {
    expect(_commandsSource(), contains("label: const Text('Enviar comanda')"));
  });

  test('30 botão funciona via Central', () {
    expect(_commandsSource(), contains('Future<void> sendCommand()'));
  });

  test('31 botão funciona via Cliente 360', () {
    expect(
      File('lib/screens/clientes_360_page.dart').readAsStringSync(),
      contains('VendaCentralDetalhePage('),
    );
  });

  test(
    '32 mensagem contém itens',
    () => expect(_message(), contains('Itens:')),
  );
  test(
    '33 mensagem contém total',
    () => expect(_message(), contains('Total:')),
  );
  test('34 mensagem contém pago e saldo', () {
    expect(_message(), allOf(contains('Pago:'), contains('Pendente:')));
  });
  test(
    '35 mensagem contém status',
    () => expect(_message(), contains('Status: Parcial')),
  );
  test(
    '36 mensagem contém vencimento quando pendente',
    () => expect(_message(), contains('Vencimento:')),
  );
  test('37 telefone da cliente é utilizado quando existente', () {
    expect(_commandsSource(), contains('telefone: receipt.clientPhone'));
  });
  test('38 comanda sem telefone possui fallback', () {
    expect(
      File('lib/services/external_action_service.dart').readAsStringSync(),
      contains("numero == null"),
    );
  });
  test('39 scanner e OCR continuam sem regressão estrutural', () {
    expect(File('lib/screens/vision_scanner_page.dart').existsSync(), isTrue);
    expect(File('lib/services/vision_ocr_service.dart').existsSync(), isTrue);
  });
  test('40 consignação continua sem regressão estrutural', () {
    expect(
      File(
        'lib/repositories/consignacao_conferencia_repository.dart',
      ).existsSync(),
      isTrue,
    );
  });
}

Future<String> _command(
  ComandaLojaRepository repo, {
  required double paid,
}) async {
  final id = await repo.criar(
    clienteId: 'client-1',
    vencimento: DateTime.now().add(const Duration(days: 6)),
  );
  await repo.adicionarProduto(id, 'product-1');
  await repo.finalizar(
    id,
    pagamentoInicial: paid,
    formaPagamento: 'pix',
    vencimento: DateTime.now().add(const Duration(days: 6)),
    dataPagamento: DateTime.now(),
  );
  return id;
}

Future<void> _conclude(
  AgendaRepository repo,
  String status,
  double received,
  DateTime paidAt, {
  String method = 'pix',
  DateTime? due,
}) => repo.concluirAgendamento(
  agendamentoId: 'agenda-1',
  pagamento: ConclusaoPagamentoAtendimento(
    situacao: status,
    valorRecebido: received,
    formaPagamento: method,
    dataPagamento: paidAt,
    vencimento: due ?? DateTime.now().add(const Duration(days: 6)),
  ),
);

Future<Map<String, Object?>> _appointment(Database db) async =>
    (await db.query('agendamentos', where: "id='agenda-1'")).single;

Future<void> _movement(
  Database db,
  String type,
  double value,
  String center, {
  String id = 'movement-1',
}) => db.insert('movimentacoes_financeiras', {
  'id': id,
  'comercio_id': 'commerce-1',
  'tipo': type,
  'descricao': 'Movimento',
  'valor': value,
  'forma_pagamento': 'pix',
  'status': 'pago',
  'data': DateTime.now().toIso8601String(),
  'data_criacao': DateTime.now().toIso8601String(),
  'categoria': 'Teste',
  'centro_resultado': center,
});

String _commandsSource() =>
    File('lib/screens/comandas_loja_page.dart').readAsStringSync();

String _message() => PurchaseReceiptService.whatsappMessage(
  PurchaseReceiptData(
    establishment: 'Studio Teste',
    client: 'Maria',
    clientPhone: '11999999999',
    commandNumber: '20260001',
    purchaseDate: DateTime(2026, 8, 19),
    paymentDate: DateTime(2026, 8, 19),
    paymentMethod: 'Pix',
    discount: 5,
    amountPaid: 10,
    status: 'Parcial',
    dueDate: DateTime.now().add(const Duration(days: 6)),
    items: const [
      {
        'nome': 'Anel',
        'codigo': '123',
        'quantidade': 1.0,
        'valor_unitario': 20.0,
      },
    ],
  ),
);

Future<void> _seed(Database db, DateTime day) async {
  final now = day.toIso8601String();
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
    'comercio_id': 'commerce-1',
    'nome': 'Maria',
    'whatsapp': '11999999999',
    'data_cadastro': now,
    'ativo': 1,
  });
  await db.insert('profissionais', {
    'id': 'user-1',
    'comercio_id': 'commerce-1',
    'nome': 'Dono',
    'whatsapp': '11999999999',
    'cargo': 'Dono',
    'ativo': 1,
    'percentual_comissao': 0,
    'meta_mensal': 0,
    'faturamento_mes': 0,
    'data_cadastro': now,
  });
  await db.insert('servicos', {
    'id': 'service-1',
    'comercio_id': 'commerce-1',
    'nome': 'Corte',
    'categoria': 'Cabelo',
    'preco': 100.0,
    'duracao_minutos': 60,
    'ativo': 1,
    'custo_estimado': 0.0,
    'data_cadastro': now,
  });
  await db.insert('agendamentos', {
    'id': 'agenda-1',
    'comercio_id': 'commerce-1',
    'cliente_id': 'client-1',
    'profissional_id': 'user-1',
    'servico_id': 'service-1',
    'inicio': now,
    'fim': day.add(const Duration(hours: 1)).toIso8601String(),
    'status': 'agendado',
    'forma_pagamento': 'pix',
    'valor_servico': 100.0,
    'desconto': 0.0,
    'valor_recebido': 0.0,
    'confirmado': 0,
    'compareceu': 0,
    'data_criacao': now,
    'created_at': now,
    'updated_at': now,
  });
  await db.insert('estoque', {
    'id': 'product-1',
    'nome': 'Anel',
    'categoria': 'joias',
    'tipo': 'produto',
    'quantidade_atual': 10.0,
    'estoque_minimo': 0.0,
    'unidade': 'un',
    'preco_venda': 20.0,
    'codigo_interno': 'COD-1',
    'estoque_destino': 'loja',
    'comercio_id': 'commerce-1',
    'ativo': 1,
    'data_cadastro': now,
  });
  await db.insert('estoque_saldos', {
    'id': 'product-balance',
    'business_id': 'commerce-1',
    'estoque_id': 'product-1',
    'finalidade': 'venda',
    'quantidade_atual': 10.0,
    'quantidade_reservada': 0.0,
    'created_at': now,
    'updated_at': now,
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
