import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/models/domain/centro_resultado.dart';
import 'package:studioflow/repositories/centro_resultado_repository.dart';
import 'package:studioflow/database/database_schema_latest.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late CentroResultadoRepository repository;
  final period = PeriodoGestao.personalizado(
    DateTime(2026, 8, 1),
    DateTime(2026, 8, 31),
  );

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    repository = CentroResultadoRepository(
      databaseProvider: () async => db,
      comercioId: 'c1',
    );
    await _schema(db);
    await db.insert('agendamentos', {
      'id': 'a1',
      'comercio_id': 'c1',
      'inicio': '2026-08-10T10:00:00',
      'status': 'concluido',
      'excluido': 0,
      'valor_servico': 100,
      'desconto': 0,
      'valor_recebido': 0,
      'forma_pagamento': 'pix',
    });
    await db.insert('pdv_vendas', {
      'id': 'v1',
      'comercio_id': 'c1',
      'data_venda': '2026-08-11T10:00:00',
      'status': 'concluida',
      'valor_total': 50,
    });
    await db.insert('estoque', {'id': 'p1', 'custo_unitario': 20});
    await db.insert('pdv_venda_itens', {
      'id': 'i1',
      'pdv_venda_id': 'v1',
      'produto_id': 'p1',
      'quantidade': 1,
    });
    await _movement(db, 's1', 60, 'receita', 'pago', 'salao');
    await _movement(db, 'l1', 50, 'receita', 'pago', 'loja');
    await _movement(db, 'g1', 10, 'receita', 'pago', 'geral');
    await _movement(db, 'n1', 5, 'receita', 'pago', null);
    await _movement(db, 'd1', 20, 'despesa', 'pago', 'geral');
    await _movement(db, 'd2', 30, 'despesa', 'pendente', 'geral');
  });

  tearDown(() => db.close());

  test(
    'Geral consolida centros uma vez e mantém composição rastreável',
    () async {
      final general = await repository.resumo(CentroResultado.geral, period);
      final salon = await repository.resumo(CentroResultado.salao, period);
      final store = await repository.resumo(CentroResultado.loja, period);

      expect(salon.faturamento, 100);
      expect(store.faturamento, 50);
      expect(general.salao, 100);
      expect(general.loja, 50);
      expect(general.administrativo, 10);
      expect(general.naoClassificado, 5);
      expect(general.faturamento, 165);
      expect(general.faturamento, salon.faturamento + store.faturamento + 15);
    },
  );

  test(
    'faturado não vira recebido e despesa pendente não reduz saldo',
    () async {
      final general = await repository.resumo(CentroResultado.geral, period);
      expect(general.recebido, 125);
      expect(general.despesas, 50);
      expect(general.saldoRealizado, 105);
      expect(general.resultado, 165 - 20 - 50);
    },
  );

  test('Loja e Salão permanecem isolados e NULL é detalhável', () async {
    final salon = await repository.resumo(CentroResultado.salao, period);
    final store = await repository.resumo(CentroResultado.loja, period);
    expect(salon.recebido, 60);
    expect(store.recebido, 50);
    final unknown = await repository.movimentos(
      centro: CentroResultado.naoClassificado,
      periodo: period,
    );
    expect(unknown.map((item) => item.id), contains('n1'));
  });

  test('read model consulta banco novo sem depender de dados', () async {
    final fresh = await databaseFactoryFfi.openDatabase(
      'centro_resultado_fresh_${DateTime.now().microsecondsSinceEpoch}.db',
      options: OpenDatabaseOptions(
        version: 39,
        onCreate: DatabaseSchemaLatest.criar,
      ),
    );
    addTearDown(fresh.close);
    final freshRepository = CentroResultadoRepository(
      databaseProvider: () async => fresh,
      comercioId: 'sem_dados',
    );
    final summary = await freshRepository.resumo(CentroResultado.geral, period);
    expect(summary.faturamento, 0);
    expect(summary.recebido, 0);
  });
}

Future<void> _movement(
  Database db,
  String id,
  double value,
  String type,
  String status,
  String? center,
) => db.insert('movimentacoes_financeiras', {
  'id': id,
  'comercio_id': 'c1',
  'descricao': id,
  'valor': value,
  'tipo': type,
  'status': status,
  'data': '2026-08-12T10:00:00',
  'centro_resultado': center,
});

Future<void> _schema(Database db) async {
  final statements = <String>[
    '''CREATE TABLE agendamentos (id TEXT, comercio_id TEXT, inicio TEXT,
      status TEXT, excluido INTEGER, valor_servico REAL, desconto REAL,
      valor_recebido REAL, forma_pagamento TEXT)''',
    'CREATE TABLE sessoes_pacotes (agendamento_id TEXT)',
    '''CREATE TABLE pacotes_vendidos (id TEXT, business_id TEXT, data_venda TEXT,
      valor_final REAL, status TEXT, deleted_at TEXT)''',
    '''CREATE TABLE pdv_vendas (id TEXT, comercio_id TEXT, data_venda TEXT,
      status TEXT, valor_total REAL)''',
    '''CREATE TABLE pdv_venda_itens (id TEXT, pdv_venda_id TEXT,
      produto_id TEXT, quantidade REAL)''',
    'CREATE TABLE estoque (id TEXT, custo_unitario REAL)',
    'CREATE TABLE pecas_unicas (id TEXT, custo REAL)',
    '''CREATE TABLE movimentacoes_financeiras (id TEXT, comercio_id TEXT,
      tipo TEXT, descricao TEXT, valor REAL, status TEXT, data TEXT,
      centro_resultado TEXT, entidade_origem TEXT, entidade_origem_id TEXT,
      observacoes TEXT)''',
    '''CREATE TABLE contas_receber_loja (comercio_id TEXT, vencimento TEXT,
      valor_total REAL, valor_recebido REAL, status TEXT)''',
    '''CREATE TABLE cobrancas (comercio_id TEXT, criado_em TEXT, valor REAL,
      status TEXT, agendamento_id TEXT)''',
    '''CREATE TABLE auditoria_estoque_consumo (comercio_id TEXT, data_hora TEXT,
      tipo_movimento TEXT, quantidade REAL, estoque_id TEXT)''',
    '''CREATE TABLE comissoes (valor_comissao REAL, agendamento_id TEXT,
      data_geracao TEXT, status TEXT, servico_id TEXT)''',
    '''CREATE TABLE pacote_comissoes (comercio_id TEXT, criada_em TEXT,
      status TEXT, valor_comissao REAL)''',
    '''CREATE TABLE comanda_comissoes (comercio_id TEXT, criado_em TEXT,
      status TEXT, valor REAL)''',
  ];
  for (final statement in statements) {
    await db.execute(statement);
  }
}
