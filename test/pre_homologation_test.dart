import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/database/migrations/migration_v13.dart';
import 'package:studioflow/models/domain/acesso.dart';
import 'package:studioflow/models/domain/anamnese.dart';
import 'package:studioflow/repositories/acesso_repository.dart';
import 'package:studioflow/repositories/agenda_completa_repository.dart';
import 'package:studioflow/repositories/anamnese_repository.dart';
import 'package:studioflow/services/session_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  late UsuarioAcesso dono;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 13,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: DatabaseSchemaLatest.criar,
      ),
    );
    final acesso = AcessoRepository(databaseProvider: () async => db);
    dono = await acesso.cadastrarComercio(
      const CadastroComercioEntrada(
        nomeComercio: 'Studio Pré-homologação',
        nomeExibicao: 'Studio Pré-homologação',
        responsavel: 'Dona Teste',
        telefone: '5511999999999',
        email: 'dona@studioflow.test',
        senha: 'Senha@123',
        permanecerConectado: false,
      ),
    );
    SessionController.instance.entrar(dono);
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('clientes', {
      'id': 'cli-1',
      'comercio_id': dono.comercioId,
      'nome': 'Cliente Teste',
      'whatsapp': '5511988888888',
      'consentimento_whatsapp': 1,
      'ativo': 1,
      'data_cadastro': now,
      'total_atendimentos': 0,
      'total_gasto': 0,
      'pontos_fidelidade': 0,
    });
    await db.insert('profissionais', {
      'id': 'pro-1',
      'comercio_id': dono.comercioId,
      'nome': 'Profissional',
      'whatsapp': '5511977777777',
      'cargo': 'cabeleireira',
      'ativo': 1,
      'percentual_comissao': 50,
      'meta_mensal': 0,
      'faturamento_mes': 0,
      'data_cadastro': now,
    });
    await db.insert('servicos', {
      'id': 'srv-1',
      'comercio_id': dono.comercioId,
      'nome': 'Corte',
      'categoria': 'Cabelo',
      'preco': 100,
      'duracao_minutos': 60,
      'ativo': 1,
      'custo_estimado': 0,
      'data_cadastro': now,
    });
  });

  tearDown(() async => db.close());

  test('migração v13 cria backup lógico sem apagar dados', () async {
    await _appointment(db, dono.comercioId, 'agenda-preservada');
    await MigrationV13.executar(db, criarBackup: true);
    expect(
      await db.query(
        'agendamentos',
        where: 'id=?',
        whereArgs: ['agenda-preservada'],
      ),
      hasLength(1),
    );
    expect(
      await db.query('backups_logicos', where: 'versao_origem=12'),
      hasLength(2),
    );
  });
  test('anamnese valida consentimento e preserva versões', () async {
    final repository = AnamneseRepository(
      databaseProvider: () async => db,
      comercioId: dono.comercioId,
      usuarioId: dono.id,
    );
    AnamneseRegistro ficha(String observacao) => AnamneseRegistro(
      id: '',
      clienteId: 'cli-1',
      comercioId: dono.comercioId,
      tipoFicha: 'geral',
      versao: 0,
      ativa: true,
      respostas: {
        for (final campo in AnamneseRegistro.camposBooleanos) campo: false,
      },
      descricaoAlergias: '',
      medicamentos: '',
      problemasPele: '',
      formatoPreferido: '',
      comprimentoPreferido: '',
      restricoes: '',
      observacoes: observacao,
      clienteConfirmouInformacoes: true,
      autorizouProcedimento: true,
      assinaturaCliente: 'Cliente Teste',
      termoVersao: '1.0',
      dataCriacao: DateTime.now(),
      dataAtualizacao: DateTime.now(),
    );

    expect((await repository.salvar(ficha('Primeira'))).versao, 1);
    expect((await repository.salvar(ficha('Segunda'))).versao, 2);
    final history = await repository.historico('cli-1');
    expect(history, hasLength(2));
    expect(history.singleWhere((item) => item.ativa).observacoes, 'Segunda');
  });

  test('cancelamento exige motivo e cancela mensagens pendentes', () async {
    await _appointment(db, dono.comercioId, 'agenda-cancelar');
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('notificacoes', {
      'id': 'not-1',
      'comercio_id': dono.comercioId,
      'tipo': 'agenda',
      'titulo': 'Lembrete',
      'mensagem': 'Mensagem',
      'status': 'pendente',
      'data_criacao': now,
      'referencia_id': 'agenda-cancelar',
    });
    await db.insert('whatsapp_fila', {
      'id': 'wa-1',
      'business_id': dono.comercioId,
      'destinatario': '5511988888888',
      'payload': '{}',
      'agendamento_id': 'agenda-cancelar',
      'status': 'simulado',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    final agenda = AgendaCompletaRepository(
      databaseProvider: () async => db,
      comercioId: dono.comercioId,
      usuarioId: dono.id,
    );
    await expectLater(
      agenda.registrarStatus(
        agendamentoId: 'agenda-cancelar',
        status: 'cancelado',
      ),
      throwsStateError,
    );
    await agenda.registrarStatus(
      agendamentoId: 'agenda-cancelar',
      status: 'cancelado',
      detalhes: 'Cliente solicitou cancelamento',
    );
    expect((await db.query('notificacoes')).single['status'], 'cancelada');
    expect((await db.query('whatsapp_fila')).single['status'], 'cancelado');
  });

  test(
    'exclusão segura é lógica, auditada e bloqueia vínculo financeiro',
    () async {
      await _appointment(db, dono.comercioId, 'agenda-excluir');
      await _appointment(db, dono.comercioId, 'agenda-bloqueada');
      final agenda = AgendaCompletaRepository(
        databaseProvider: () async => db,
        comercioId: dono.comercioId,
        usuarioId: dono.id,
      );
      await agenda.excluirSeguro(
        agendamentoId: 'agenda-excluir',
        motivo: 'Cadastro criado por engano',
      );
      final deleted = (await db.query(
        'agendamentos',
        where: 'id=?',
        whereArgs: ['agenda-excluir'],
      )).single;
      expect(deleted['excluido'], 1);
      expect(await db.query('agendamento_exclusoes'), hasLength(1));

      await db.insert('movimentacoes_financeiras', {
        'id': 'fin-1',
        'comercio_id': dono.comercioId,
        'tipo': 'entrada',
        'descricao': 'Pagamento',
        'valor': 100,
        'status': 'pago',
        'data': DateTime.now().toIso8601String(),
        'data_criacao': DateTime.now().toIso8601String(),
        'agendamento_id': 'agenda-bloqueada',
      });
      await expectLater(
        agenda.excluirSeguro(
          agendamentoId: 'agenda-bloqueada',
          motivo: 'Tentativa de exclusão',
        ),
        throwsStateError,
      );
    },
  );
}

Future<void> _appointment(Database db, String businessId, String id) async {
  final start = DateTime.now().add(const Duration(days: 2));
  await db.insert('agendamentos', {
    'id': id,
    'comercio_id': businessId,
    'cliente_id': 'cli-1',
    'profissional_id': 'pro-1',
    'servico_id': 'srv-1',
    'inicio': start.toIso8601String(),
    'fim': start.add(const Duration(hours: 1)).toIso8601String(),
    'status': 'agendado',
    'valor_servico': 100,
    'desconto': 0,
    'valor_recebido': 0,
    'confirmado': 0,
    'compareceu': 0,
    'data_criacao': DateTime.now().toIso8601String(),
  });
}
