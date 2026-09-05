import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/models/domain/acesso.dart';
import 'package:studioflow/repositories/acesso_repository.dart';
import 'package:studioflow/repositories/accounts_payable_repository.dart';
import 'package:studioflow/repositories/agenda_completa_repository.dart';
import 'package:studioflow/repositories/agenda_repository.dart';
import 'package:studioflow/repositories/notification_center_repository.dart';
import 'package:studioflow/services/session_controller.dart';

class _FakeNotifications implements LocalNotificationGateway {
  final scheduled = <int>[];
  final canceled = <int>[];

  @override
  Future<void> cancel(int id) async => canceled.add(id);

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime date,
    String? payload,
    required String category,
  }) async => scheduled.add(id);
}

void main() {
  sqfliteFfiInit();

  late Database db;
  late UsuarioAcesso owner;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 47,
        onCreate: DatabaseSchemaLatest.criar,
      ),
    );
    owner = await AcessoRepository(databaseProvider: () async => db)
        .cadastrarComercio(
          const CadastroComercioEntrada(
            nomeComercio: 'Studio A',
            nomeExibicao: 'Studio A',
            responsavel: 'Dona',
            telefone: '11999999999',
            email: 'owner@studio.test',
            senha: 'Senha@123',
            permanecerConectado: false,
          ),
        );
    SessionController.instance.entrar(owner);
  });

  tearDown(() async {
    SessionController.instance.cancelarSincronizacaoEmTeste();
    await db.close();
  });

  test('edição persiste serviço novo mesmo quando a duração é igual', () async {
    final now = DateTime(2026, 9, 5);
    await db.insert('clientes', {
      'id': 'c1',
      'comercio_id': owner.comercioId,
      'nome': 'Ana',
      'whatsapp': '',
      'data_cadastro': now.toIso8601String(),
    });
    await db.insert('profissionais', {
      'id': 'p1',
      'comercio_id': owner.comercioId,
      'nome': 'Bia',
      'whatsapp': '',
      'cargo': 'Manicure',
      'data_cadastro': now.toIso8601String(),
    });
    for (final service in [
      ('mao', 'Mão', 30, 25.0),
      ('pe_mao', 'Pé e Mão', 30, 50.0),
    ]) {
      await db.insert('servicos', {
        'id': service.$1,
        'comercio_id': owner.comercioId,
        'nome': service.$2,
        'categoria': 'Unhas',
        'preco': service.$4,
        'duracao_minutos': service.$3,
        'data_cadastro': now.toIso8601String(),
      });
    }
    await db.insert('agendamentos', {
      'id': 'a1',
      'comercio_id': owner.comercioId,
      'cliente_id': 'c1',
      'profissional_id': 'p1',
      'servico_id': 'mao',
      'inicio': DateTime(2026, 9, 8, 10).toIso8601String(),
      'fim': DateTime(2026, 9, 8, 10, 30).toIso8601String(),
      'valor_servico': 25,
      'data_criacao': now.toIso8601String(),
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    await AgendaCompletaRepository(
      databaseProvider: () async => db,
      comercioId: owner.comercioId,
      usuarioId: owner.id,
    ).atualizarCompleto(
      AgendamentoRegistro(
        id: 'a1',
        clienteId: 'c1',
        clienteNome: 'Ana',
        profissionalId: 'p1',
        profissionalNome: 'Bia',
        servicoId: 'pe_mao',
        servicoNome: 'Pé e Mão',
        inicio: DateTime(2026, 9, 8, 10),
        fim: DateTime(2026, 9, 8, 10, 30),
        status: 'agendado',
        valorServico: 50,
        desconto: 0,
        valorRecebido: 0,
        confirmado: false,
        compareceu: false,
        dataCriacao: now,
      ),
    );

    final saved = (await db.query(
      'agendamentos',
      where: 'id = ?',
      whereArgs: ['a1'],
    )).single;
    expect(saved['servico_id'], 'pe_mao');
    expect(saved['valor_servico'], 50);
    expect(saved['fim'], DateTime(2026, 9, 8, 10, 30).toIso8601String());
  });

  test(
    'conta respeita negócio, agenda alertas e recorrência sem duplicar',
    () async {
      final fake = _FakeNotifications();
      final center = NotificationCenterRepository(
        databaseProvider: () async => db,
        businessId: owner.comercioId,
        gateway: fake,
      );
      final repository = AccountsPayableRepository(
        databaseProvider: () async => db,
        businessId: owner.comercioId,
        notifications: center,
      );
      final now = DateTime.now();
      final item = AccountPayable(
        id: 'rent-1',
        businessId: owner.comercioId,
        description: 'Aluguel',
        category: 'Estrutura',
        amount: 1350,
        type: 'fixa',
        dueDate: now.add(const Duration(days: 10)),
        recurrence: 'mensal',
        createdAt: now,
        updatedAt: now,
      );
      await repository.save(item);
      expect(fake.scheduled, hasLength(2));
      expect(await repository.list(), hasLength(1));

      await repository.markPaid(item.id, 'Pix');
      expect(await repository.list(), hasLength(2));
      await expectLater(repository.markPaid(item.id, 'Pix'), completes);
      expect(await repository.list(), hasLength(2));
      expect(fake.canceled, isNotEmpty);

      expect(
        () => repository.save(
          AccountPayable(
            id: 'foreign',
            businessId: 'business-b',
            description: 'Não pode cruzar',
            category: 'Teste',
            amount: 1,
            type: 'variavel',
            dueDate: now,
            createdAt: now,
            updatedAt: now,
          ),
        ),
        throwsStateError,
      );
    },
  );

  test('preferência desativada impede alerta local', () async {
    final fake = _FakeNotifications();
    final center = NotificationCenterRepository(
      databaseProvider: () async => db,
      businessId: owner.comercioId,
      gateway: fake,
    );
    await center.setEnabled('agenda', 'local', false);
    await center.schedule(
      key: 'appointment:a1:2h',
      type: 'agenda_2h',
      category: 'agenda',
      entity: 'appointment',
      entityId: 'a1',
      title: 'Ana em 2 horas',
      body: 'Pé e Mão às 14h',
      date: DateTime.now().add(const Duration(hours: 2)),
      route: '/agenda/a1',
    );
    expect(fake.scheduled, isEmpty);
    expect(await center.list(category: 'agenda'), hasLength(1));
  });

  test('edição reagenda, cards calculam banco e vencida não duplica', () async {
    final fake = _FakeNotifications();
    final center = NotificationCenterRepository(
      databaseProvider: () async => db,
      businessId: owner.comercioId,
      gateway: fake,
    );
    final repository = AccountsPayableRepository(
      databaseProvider: () async => db,
      businessId: owner.comercioId,
      notifications: center,
    );
    final now = DateTime(2026, 9, 5, 12);
    final item = AccountPayable(
      id: 'energy',
      businessId: owner.comercioId,
      description: 'Energia',
      category: 'Estrutura',
      amount: 280.40,
      type: 'variavel',
      dueDate: DateTime(2026, 9, 5),
      createdAt: now,
      updatedAt: now,
    );
    await repository.save(item);
    await repository.save(
      item.copyWith(
        description: 'Energia matriz',
        dueDate: DateTime(2026, 9, 6),
      ),
    );
    expect(fake.canceled, isNotEmpty);
    expect((await repository.get(item.id))!.description, 'Energia matriz');
    final summary = await repository.summary(now);
    expect(summary.dueTomorrow, 1);
    expect(summary.pendingMonth, 280.40);

    await repository.save(
      AccountPayable(
        id: 'internet',
        businessId: owner.comercioId,
        description: 'Internet',
        category: 'Estrutura',
        amount: 100,
        type: 'fixa',
        dueDate: DateTime(2026, 9, 3),
        recurrence: 'mensal',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await repository.refreshOverdue(now);
    await repository.refreshOverdue(now);
    final overdue = (await center.list()).where(
      (row) => row['tipo'] == 'contas_pagar_vencida',
    );
    expect(overdue, hasLength(1));
  });

  test('deep link só aceita entidade do negócio autenticado', () async {
    final center = NotificationCenterRepository(
      databaseProvider: () async => db,
      businessId: owner.comercioId,
      gateway: _FakeNotifications(),
    );
    final other = NotificationCenterRepository(
      databaseProvider: () async => db,
      businessId: 'business-b',
      gateway: _FakeNotifications(),
    );
    final now = DateTime.now();
    await AccountsPayableRepository(
      databaseProvider: () async => db,
      businessId: owner.comercioId,
      notifications: center,
    ).save(
      AccountPayable(
        id: 'safe-link',
        businessId: owner.comercioId,
        description: 'Conta segura',
        category: 'Teste',
        amount: 10,
        type: 'variavel',
        dueDate: now.add(const Duration(days: 2)),
        createdAt: now,
        updatedAt: now,
      ),
    );
    expect(
      await center.entityBelongsToBusiness('account_payable', 'safe-link'),
      isTrue,
    );
    expect(
      await other.entityBelongsToBusiness('account_payable', 'safe-link'),
      isFalse,
    );
    expect(
      await center.entityBelongsToBusiness('unknown', 'safe-link'),
      isFalse,
    );
  });
}
