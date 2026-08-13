import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/models/domain/acesso.dart';
import 'package:studioflow/models/domain/centro_resultado.dart';
import 'package:studioflow/repositories/acesso_repository.dart';
import 'package:studioflow/repositories/centro_resultado_repository.dart';
import 'package:studioflow/repositories/pagamento_repository.dart';
import 'package:studioflow/services/session_controller.dart';

void main() {
  sqfliteFfiInit();

  group('recebimentos reais de serviços', () {
    late Database db;
    late UsuarioAcesso usuario;
    late PagamentoRepository pagamentos;
    late DateTime data;

    setUp(() async {
      final agora = DateTime.now().toUtc();
      data = DateTime(agora.year, agora.month, agora.day, 10);
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 39,
          onCreate: DatabaseSchemaLatest.criar,
        ),
      );
      usuario = await AcessoRepository(databaseProvider: () async => db)
          .cadastrarComercio(
            const CadastroComercioEntrada(
              nomeComercio: 'Salão Financeiro',
              nomeExibicao: 'Salão Financeiro',
              responsavel: 'Responsável',
              telefone: '11999990000',
              email: 'financeiro@teste.local',
              senha: 'Senha@123',
              permanecerConectado: false,
            ),
          );
      SessionController.instance.entrar(usuario);
      await _dadosBase(db, usuario.comercioId, data);
      pagamentos = PagamentoRepository(
        databaseProvider: () async => db,
        comercioId: usuario.comercioId,
        usuarioId: usuario.id,
      );
    });

    tearDown(() async => db.close());

    test('concluir sem pagamento fatura, mas não cria entrada', () async {
      await db.update(
        'agendamentos',
        {'status': 'concluido', 'compareceu': 1},
        where: 'id=?',
        whereArgs: ['agenda_1'],
      );

      expect(await _movimentos(db, 'agenda_1'), isEmpty);
      final resumo = await _resumo(db, usuario.comercioId, data);
      expect(resumo.faturamento, 100);
      expect(resumo.recebido, 0);
      expect(resumo.aReceber, 100);
    });

    test('parcial, reexecução e segundo pagamento não duplicam', () async {
      await db.update(
        'agendamentos',
        {'status': 'concluido'},
        where: 'id=?',
        whereArgs: ['agenda_1'],
      );
      expect(
        await pagamentos.registrarPagamentoAtendimento(
          agendamentoId: 'agenda_1',
          valor: 40,
          formaPagamento: 'pix',
          referencia: 'pagamento_1',
        ),
        isTrue,
      );
      expect(
        await pagamentos.registrarPagamentoAtendimento(
          agendamentoId: 'agenda_1',
          valor: 40,
          formaPagamento: 'pix',
          referencia: 'pagamento_1',
        ),
        isFalse,
      );
      expect((await _movimentos(db, 'agenda_1')), hasLength(1));
      expect(await _valorRecebido(db, 'agenda_1'), 40);

      await pagamentos.registrarPagamentoAtendimento(
        agendamentoId: 'agenda_1',
        valor: 60,
        formaPagamento: 'dinheiro',
        referencia: 'pagamento_2',
      );
      expect((await _movimentos(db, 'agenda_1')), hasLength(2));
      expect(await _valorRecebido(db, 'agenda_1'), 100);
      final resumo = await _resumo(db, usuario.comercioId, data);
      expect(resumo.faturamento, 100);
      expect(resumo.recebido, 100);
      expect(resumo.aReceber, 0);
    });

    test('cobrança pendente não recebe; confirmação recebe uma vez', () async {
      final cobranca = await pagamentos.criarCobranca(
        agendamentoId: 'agenda_1',
        clienteId: 'cliente_1',
        valor: 25,
        descricao: 'Sinal',
        forma: 'dinheiro',
      );
      expect(await _movimentos(db, 'agenda_1'), isEmpty);

      await pagamentos.confirmarManual(cobranca.id);
      await pagamentos.confirmarManual(cobranca.id);
      final movimentos = await _movimentos(db, 'agenda_1');
      expect(movimentos, hasLength(1));
      expect(movimentos.single['valor'], 25);
      expect(movimentos.single['entidade_origem'], 'cobranca');
      expect(await _valorRecebido(db, 'agenda_1'), 25);
    });

    test('sinal e restante somam sem duplicar', () async {
      final sinal = await pagamentos.criarCobranca(
        agendamentoId: 'agenda_1',
        valor: 20,
        descricao: 'Sinal',
        forma: 'dinheiro',
      );
      await pagamentos.confirmarManual(sinal.id);
      await pagamentos.registrarPagamentoAtendimento(
        agendamentoId: 'agenda_1',
        valor: 80,
        formaPagamento: 'dinheiro',
        referencia: 'restante_1',
      );
      expect(await _valorRecebido(db, 'agenda_1'), 100);
      expect(await _movimentos(db, 'agenda_1'), hasLength(2));
    });

    test('estorno gera contramovimento e reabre saldo', () async {
      await db.update(
        'agendamentos',
        {'status': 'concluido'},
        where: 'id=?',
        whereArgs: ['agenda_1'],
      );
      await pagamentos.registrarPagamentoAtendimento(
        agendamentoId: 'agenda_1',
        valor: 100,
        formaPagamento: 'pix',
        referencia: 'integral_1',
      );
      await pagamentos.estornarRecebimentoAtendimento(
        movimentoId: 'recebimento_integral_1',
        motivo: 'Pagamento devolvido',
      );

      final movimentos = await _movimentos(db, 'agenda_1', todos: true);
      expect(movimentos, hasLength(2));
      expect(
        movimentos.where((m) => m['tipo'] == 'estorno').single['valor'],
        -100,
      );
      expect(await _valorRecebido(db, 'agenda_1'), 0);
      final resumo = await _resumo(db, usuario.comercioId, data);
      expect(resumo.faturamento, 100);
      expect(resumo.recebido, 0);
      expect(resumo.aReceber, 100);
    });
  });
}

Future<void> _dadosBase(Database db, String comercioId, DateTime data) async {
  final iso = data.toIso8601String();
  await db.insert('clientes', {
    'id': 'cliente_1',
    'comercio_id': comercioId,
    'nome': 'Cliente',
    'whatsapp': '11999990001',
    'data_cadastro': iso,
  });
  await db.insert('profissionais', {
    'id': 'prof_1',
    'comercio_id': comercioId,
    'nome': 'Profissional',
    'whatsapp': '11999990002',
    'cargo': 'Profissional',
    'ativo': 1,
    'percentual_comissao': 0,
    'meta_mensal': 0,
    'faturamento_mes': 0,
    'data_cadastro': iso,
  });
  await db.insert('servicos', {
    'id': 'serv_1',
    'comercio_id': comercioId,
    'nome': 'Serviço',
    'categoria': 'Teste',
    'preco': 100,
    'duracao_minutos': 60,
    'ativo': 1,
    'custo_estimado': 0,
    'data_cadastro': iso,
  });
  await db.insert('agendamentos', {
    'id': 'agenda_1',
    'comercio_id': comercioId,
    'cliente_id': 'cliente_1',
    'profissional_id': 'prof_1',
    'servico_id': 'serv_1',
    'inicio': iso,
    'fim': data.add(const Duration(hours: 1)).toIso8601String(),
    'status': 'agendado',
    'forma_pagamento': 'pix',
    'valor_servico': 100,
    'desconto': 0,
    'valor_recebido': 0,
    'confirmado': 0,
    'compareceu': 0,
    'data_criacao': iso,
    'created_at': iso,
    'updated_at': iso,
  });
}

Future<List<Map<String, Object?>>> _movimentos(
  Database db,
  String agendaId, {
  bool todos = false,
}) => db.query(
  'movimentacoes_financeiras',
  where: todos ? 'agendamento_id=?' : "agendamento_id=? AND status='pago'",
  whereArgs: [agendaId],
);

Future<double> _valorRecebido(Database db, String agendaId) async =>
    ((await db.query(
              'agendamentos',
              columns: ['valor_recebido'],
              where: 'id=?',
              whereArgs: [agendaId],
            )).single['valor_recebido']
            as num)
        .toDouble();

Future<ResumoCentroResultado> _resumo(
  Database db,
  String comercioId,
  DateTime data,
) =>
    CentroResultadoRepository(
      databaseProvider: () async => db,
      comercioId: comercioId,
    ).resumo(
      CentroResultado.salao,
      PeriodoGestao(
        inicio: DateTime(data.year, data.month, data.day),
        fimExclusivo: DateTime(data.year, data.month, data.day + 1),
        tipo: PeriodoGestaoTipo.personalizado,
      ),
    );
