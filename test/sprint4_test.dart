import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_schema.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/database/migrations/migration_v2_impl.dart';
import 'package:studioflow/database/migrations/migration_v2_triggers.dart';
import 'package:studioflow/database/migrations/migration_v3.dart';
import 'package:studioflow/models/domain/acesso.dart';
import 'package:studioflow/models/domain/atendimento.dart';
import 'package:studioflow/repositories/acesso_repository.dart';
import 'package:studioflow/repositories/agenda_completa_repository.dart';
import 'package:studioflow/repositories/agenda_repository.dart';
import 'package:studioflow/repositories/atendimento_ia_repository.dart';
import 'package:studioflow/repositories/cliente_360_repository.dart';
import 'package:studioflow/repositories/pagamento_repository.dart';
import 'package:studioflow/services/pix_payload_service.dart';
import 'package:studioflow/services/session_controller.dart';

void main() {
  sqfliteFfiInit();

  group('Sprint 4 - agenda, clientes, pagamentos e IA', () {
    late Database db;
    late UsuarioAcesso dono;
    late AgendaCompletaRepository agenda;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 4,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: DatabaseSchemaLatest.criar,
        ),
      );
      final acesso = AcessoRepository(databaseProvider: () async => db);
      dono = await acesso.cadastrarComercio(
        const CadastroComercioEntrada(
          nomeComercio: 'Salão Sprint 4',
          nomeExibicao: 'Sprint 4',
          responsavel: 'Pessoa Dona',
          telefone: '11999990000',
          email: 'dono@sprint4.test',
          senha: 'Senha@123',
          permanecerConectado: false,
        ),
      );
      SessionController.instance.entrar(dono);
      await _dadosBasicos(db, dono.comercioId);
      agenda = AgendaCompletaRepository(
        databaseProvider: () async => db,
        comercioId: dono.comercioId,
        usuarioId: dono.id,
      );
    });

    tearDown(() async => db.close());

    test(
      'migração v3 para v4 preserva clientes e cria backup lógico',
      () async {
        await db.close();
        final caminho = join(
          Directory.systemTemp.path,
          'studioflow_sprint4_migration.db',
        );
        await databaseFactoryFfi.deleteDatabase(caminho);
        addTearDown(() => databaseFactoryFfi.deleteDatabase(caminho));
        db = await databaseFactoryFfi.openDatabase(
          caminho,
          options: OpenDatabaseOptions(
            version: 3,
            onCreate: (db, _) async {
              await DatabaseSchema.criar(db, 1);
              await MigrationV2.executar(db, criarBackup: false);
              await MigrationV2Triggers.executar(db);
              await MigrationV3.executar(db, criarBackup: false);
            },
          ),
        );
        await db.insert('clientes', {
          'id': 'cliente_v3',
          'comercio_id': MigrationV2.comercioLegado,
          'nome': 'Cliente preservada',
          'whatsapp': '11911112222',
          'data_cadastro': DateTime(2026).toIso8601String(),
        });
        await db.close();
        db = await databaseFactoryFfi.openDatabase(
          caminho,
          options: OpenDatabaseOptions(
            version: 4,
            onUpgrade: DatabaseSchemaLatest.migrar,
          ),
        );
        final cliente = await db.query(
          'clientes',
          where: 'id = ?',
          whereArgs: ['cliente_v3'],
        );
        final backup = await db.query(
          'backups_logicos',
          where: 'versao_origem = ? AND tabela = ?',
          whereArgs: [3, 'clientes'],
        );
        expect(cliente.single['nome'], 'Cliente preservada');
        expect(cliente.single['consentimento_whatsapp'], 0);
        expect(backup, isNotEmpty);
        expect(await _tabelaExiste(db, 'configuracoes_ia'), isTrue);
        expect(await _tabelaExiste(db, 'cobrancas'), isTrue);
      },
    );

    test('agendamento por encaixe persiste no modelo e no mapa', () {
      final registro = AgendamentoRegistro(
        id: 'encaixe_1',
        clienteId: 'cliente_1',
        clienteNome: 'Cliente Um',
        profissionalId: 'prof_1',
        profissionalNome: 'Rafa',
        servicoId: 'servico_1',
        servicoNome: 'Corte',
        inicio: DateTime(2026, 7, 23, 9),
        fim: DateTime(2026, 7, 23, 10),
        status: 'agendado',
        valorServico: 50,
        desconto: 0,
        valorRecebido: 0,
        confirmado: false,
        compareceu: false,
        encaixe: true,
        observacoes: '',
        dataCriacao: DateTime(2026, 7, 22),
      );
      final mapa = registro.paraMapa()
        ..['cliente_nome'] = 'Cliente Um'
        ..['profissional_nome'] = 'Rafa'
        ..['servico_nome'] = 'Corte';
      expect(mapa['encaixe'], 1);
      expect(AgendamentoRegistro.doMapa(mapa).encaixe, isTrue);
    });

    test('disponibilidade respeita jornada, agenda e bloqueios', () async {
      final data = DateTime(2026, 7, 23);
      await agenda.salvarHorario(
        HorarioProfissional(
          id: 'horario_teste',
          profissionalId: 'prof_1',
          diaSemana: data.weekday,
          inicio: '09:00',
          fim: '12:00',
        ),
      );
      await _agendamento(
        db,
        dono.comercioId,
        id: 'agenda_ocupada',
        inicio: DateTime(2026, 7, 23, 10),
        fim: DateTime(2026, 7, 23, 11),
      );
      var livres = await agenda.horariosDisponiveis(
        profissionalId: 'prof_1',
        data: data,
        duracaoMinutos: 60,
        intervaloMinutos: 30,
      );
      expect(livres.map((e) => e.hour), [9, 11]);
      await agenda.adicionarBloqueio(
        BloqueioAgenda(
          id: 'bloqueio_teste',
          profissionalId: 'prof_1',
          inicio: DateTime(2026, 7, 23, 11),
          fim: DateTime(2026, 7, 23, 12),
          tipo: 'folga',
          motivo: 'Compromisso',
        ),
      );
      livres = await agenda.horariosDisponiveis(
        profissionalId: 'prof_1',
        data: data,
        duracaoMinutos: 60,
        intervaloMinutos: 30,
      );
      expect(livres.map((e) => e.hour), [9]);
    });

    test('disponibilidade respeita vínculo profissional e serviço', () async {
      final data = DateTime(2026, 7, 23);
      await agenda.salvarHorario(
        HorarioProfissional(
          id: 'horario_vinculo',
          profissionalId: 'prof_1',
          diaSemana: data.weekday,
          inicio: '09:00',
          fim: '12:00',
        ),
      );
      await db.insert('profissionais', {
        'id': 'prof_2',
        'comercio_id': dono.comercioId,
        'nome': 'Bia',
        'whatsapp': '11999990003',
        'cargo': 'Cabeleireira',
        'ativo': 1,
        'percentual_comissao': 50,
        'meta_mensal': 0,
        'faturamento_mes': 0,
        'data_cadastro': DateTime(2026, 7, 22).toIso8601String(),
      });
      await db.insert('profissional_servicos', {
        'profissional_id': 'prof_2',
        'servico_id': 'servico_1',
        'business_id': dono.comercioId,
        'ativo': 1,
      });

      expect(
        await agenda.horariosDisponiveis(
          profissionalId: 'prof_1',
          data: data,
          duracaoMinutos: 60,
          servicoId: 'servico_1',
        ),
        isEmpty,
      );
    });

    test(
      'bloqueio pode ser editado, excluído e preserva horário livre',
      () async {
        final data = DateTime(2026, 7, 25);
        await agenda.salvarHorario(
          HorarioProfissional(
            id: 'horario_bloqueio_crud',
            profissionalId: 'prof_1',
            diaSemana: data.weekday,
            inicio: '09:00',
            fim: '18:00',
          ),
        );
        await agenda.adicionarBloqueio(
          BloqueioAgenda(
            id: 'bloqueio_crud',
            profissionalId: 'prof_1',
            inicio: DateTime(2026, 7, 25, 13, 30),
            fim: DateTime(2026, 7, 25, 14),
            tipo: 'bloqueio',
            motivo: 'Compromisso',
          ),
        );
        await agenda.adicionarBloqueio(
          BloqueioAgenda(
            id: 'bloqueio_crud',
            profissionalId: 'prof_1',
            inicio: DateTime(2026, 7, 25, 14),
            fim: DateTime(2026, 7, 25, 15),
            tipo: 'bloqueio',
            motivo: 'Editado',
          ),
        );
        final bloqueios = await agenda.listarBloqueios(aPartirDe: data);
        expect(bloqueios, hasLength(1));
        expect(bloqueios.single.inicio.hour, 14);
        expect(bloqueios.single.motivo, 'Editado');

        final livres = await agenda.horariosDisponiveis(
          profissionalId: 'prof_1',
          data: data,
          duracaoMinutos: 60,
          intervaloMinutos: 60,
        );
        expect(livres.any((hora) => hora.hour == 14), isFalse);
        expect(livres.any((hora) => hora.hour == 15), isTrue);

        await agenda.removerBloqueio('bloqueio_crud');
        expect(await agenda.listarBloqueios(aPartirDe: data), isEmpty);
      },
    );

    test('bloqueio de dia inteiro impede todos os horários', () async {
      final data = DateTime(2026, 7, 26);
      await agenda.salvarHorario(
        HorarioProfissional(
          id: 'horario_dia_inteiro',
          profissionalId: 'prof_1',
          diaSemana: data.weekday,
          inicio: '09:00',
          fim: '18:00',
        ),
      );
      await agenda.adicionarBloqueio(
        BloqueioAgenda(
          id: 'bloqueio_dia_inteiro',
          profissionalId: 'prof_1',
          inicio: data,
          fim: data.add(const Duration(days: 1)),
          tipo: 'dia_inteiro',
          motivo: 'Folga',
        ),
      );
      expect(
        await agenda.horariosDisponiveis(
          profissionalId: 'prof_1',
          data: data,
          duracaoMinutos: 30,
        ),
        isEmpty,
      );
    });

    test('reagendamento registra histórico e impede conflito', () async {
      await _agendamento(
        db,
        dono.comercioId,
        id: 'agenda_reagendar',
        inicio: DateTime(2026, 7, 24, 9),
        fim: DateTime(2026, 7, 24, 10),
      );
      await agenda.reagendar(
        agendamentoId: 'agenda_reagendar',
        novoInicio: DateTime(2026, 7, 24, 11),
        novoFim: DateTime(2026, 7, 24, 12),
        motivo: 'Pedido da cliente',
      );
      final salvo = await db.query(
        'agendamentos',
        where: 'id = ?',
        whereArgs: ['agenda_reagendar'],
      );
      final historico = await agenda.listarHistorico('agenda_reagendar');
      expect(
        salvo.single['inicio'],
        DateTime(2026, 7, 24, 11).toIso8601String(),
      );
      expect(historico.single.acao, 'reagendamento');
      await _agendamento(
        db,
        dono.comercioId,
        id: 'agenda_conflito',
        inicio: DateTime(2026, 7, 24, 13),
        fim: DateTime(2026, 7, 24, 14),
      );
      await expectLater(
        agenda.reagendar(
          agendamentoId: 'agenda_reagendar',
          novoInicio: DateTime(2026, 7, 24, 13, 30),
          novoFim: DateTime(2026, 7, 24, 14, 30),
        ),
        throwsA(isA<ConflitoAgendaException>()),
      );
    });

    test('cliente 360 reúne agenda, faltas, recebimentos e compras', () async {
      await _agendamento(
        db,
        dono.comercioId,
        id: 'agenda_cliente',
        inicio: DateTime(2026, 7, 22, 9),
        fim: DateTime(2026, 7, 22, 10),
        status: 'faltou',
        valorRecebido: 25,
      );
      await db.insert('vendas', {
        'id': 'venda_cliente',
        'numero': 'V-1',
        'comercio_id': dono.comercioId,
        'cliente_id': 'cliente_1',
        'usuario_id': dono.id,
        'subtotal': 30,
        'desconto': 0,
        'total': 30,
        'status': 'concluida',
        'criada_em': DateTime(2026, 7, 22).toIso8601String(),
      });
      final resumo = await Cliente360Repository(
        databaseProvider: () async => db,
        comercioId: dono.comercioId,
      ).carregar('cliente_1');
      expect(resumo.agendamentos, 2);
      expect(resumo.faltas, 1);
      expect(resumo.recebidoServicos, 25);
      expect(resumo.comprasProdutos, 30);
    });

    test(
      'Pix gera payload válido e cobrança exige confirmação manual',
      () async {
        const pix = PixPayloadService();
        final payload = pix.gerar(
          chave: 'pix@sprint4.test',
          nomeRecebedor: 'Salão Sprint Quatro',
          cidade: 'São Paulo',
          valor: 50,
          referencia: 'TESTE123',
        );
        expect(payload, startsWith('000201010212'));
        expect(payload, contains('br.gov.bcb.pix'));
        expect(
          payload.substring(payload.length - 4),
          matches(RegExp(r'^[0-9A-F]{4}$')),
        );
        final pagamentos = PagamentoRepository(
          databaseProvider: () async => db,
          comercioId: dono.comercioId,
          usuarioId: dono.id,
        );
        await pagamentos.salvarConfiguracao(
          ConfiguracaoPagamento(
            comercioId: dono.comercioId,
            chavePix: 'pix@sprint4.test',
            tipoChave: 'email',
            nomeRecebedor: 'Salão Sprint Quatro',
            cidadeRecebedor: 'São Paulo',
            mensagemCobranca: 'Segue o sinal.',
            tipoSinal: 'percentual',
            valorSinal: 20,
            prazoHoras: 24,
            politicaCancelamento: 'Avisar com antecedência.',
          ),
        );
        final cobranca = await pagamentos.criarCobranca(
          agendamentoId: 'agenda_base',
          clienteId: 'cliente_1',
          valor: 20,
          descricao: 'Sinal',
        );
        expect(cobranca.status, 'pendente');
        await pagamentos.confirmarManual(cobranca.id);
        final salva = await pagamentos.listarCobrancas();
        expect(salva.single.status, 'confirmado_manual');
        final agendamento = await db.query(
          'agendamentos',
          where: 'id = ?',
          whereArgs: ['agenda_base'],
        );
        expect(agendamento.single['sinal_status'], 'confirmado_manual');
      },
    );

    test(
      'simulador usa serviços reais, FAQ e mantém comércio isolado',
      () async {
        final ia = AtendimentoIaRepository(
          databaseProvider: () async => db,
          comercioId: dono.comercioId,
        );
        await ia.salvarFaq(
          const FaqIa(
            id: 'faq_1',
            pergunta: 'Vocês têm estacionamento?',
            resposta: 'Temos estacionamento conveniado.',
          ),
        );
        final conversa = await ia.iniciarConversa();
        final servicos = await ia.responder(
          comercioId: dono.comercioId,
          conversaId: conversa,
          mensagem: 'Quais serviços e preços?',
        );
        expect(servicos, contains('Corte'));
        expect(servicos, contains('R\$ 50.00'));
        final faq = await ia.responder(
          comercioId: dono.comercioId,
          conversaId: conversa,
          mensagem: 'Tem estacionamento?',
        );
        expect(faq, 'Temos estacionamento conveniado.');
        await expectLater(
          ia.responder(
            comercioId: 'outro_comercio',
            conversaId: conversa,
            mensagem: 'teste',
          ),
          throwsStateError,
        );
        expect(await ia.listarMensagens(conversa), hasLength(5));
      },
    );
  });
}

Future<bool> _tabelaExiste(Database db, String nome) async =>
    (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [nome],
    )).isNotEmpty;

Future<void> _dadosBasicos(Database db, String comercioId) async {
  final agora = DateTime(2026, 7, 22).toIso8601String();
  await db.insert('profissionais', {
    'id': 'prof_1',
    'comercio_id': comercioId,
    'nome': 'Rafa',
    'whatsapp': '11999990001',
    'cargo': 'Cabeleireiro',
    'ativo': 1,
    'percentual_comissao': 50,
    'meta_mensal': 0,
    'faturamento_mes': 0,
    'data_cadastro': agora,
  });
  await db.insert('servicos', {
    'id': 'servico_1',
    'comercio_id': comercioId,
    'nome': 'Corte',
    'categoria': 'Cabelo',
    'preco': 50,
    'duracao_minutos': 60,
    'ativo': 1,
    'custo_estimado': 0,
    'data_cadastro': agora,
  });
  await db.insert('clientes', {
    'id': 'cliente_1',
    'comercio_id': comercioId,
    'nome': 'Cliente Um',
    'whatsapp': '11999990002',
    'data_cadastro': agora,
  });
  await _agendamento(
    db,
    comercioId,
    id: 'agenda_base',
    inicio: DateTime(2026, 7, 25, 9),
    fim: DateTime(2026, 7, 25, 10),
  );
}

Future<void> _agendamento(
  Database db,
  String comercioId, {
  required String id,
  required DateTime inicio,
  required DateTime fim,
  String status = 'agendado',
  double valorRecebido = 0,
}) => db.insert('agendamentos', {
  'id': id,
  'comercio_id': comercioId,
  'cliente_id': 'cliente_1',
  'profissional_id': 'prof_1',
  'servico_id': 'servico_1',
  'inicio': inicio.toIso8601String(),
  'fim': fim.toIso8601String(),
  'status': status,
  'valor_servico': 50,
  'desconto': 0,
  'valor_recebido': valorRecebido,
  'confirmado': status == 'confirmado' ? 1 : 0,
  'compareceu': status == 'concluido' ? 1 : 0,
  'data_criacao': DateTime(2026, 7, 22).toIso8601String(),
  'created_at': DateTime(2026, 7, 22).toIso8601String(),
  'updated_at': DateTime(2026, 7, 22).toIso8601String(),
});
