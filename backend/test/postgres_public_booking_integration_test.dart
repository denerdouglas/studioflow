import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:studioflow_backend/studioflow_backend.dart';
import 'package:test/test.dart';

void main() {
  final url = Platform.environment['POSTGRES_TEST_URL'];
  test(
    'PostgreSQL público é transacional, sincronizado e concorrente',
    () async {
      final store = PostgresBackendStore.fromUrl(url!);
      addTearDown(store.close);
      final suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final business = 'pg_business_$suffix';
      final otherBusiness = 'pg_other_$suffix';
      final owner = 'pg_owner_$suffix';
      final otherOwner = 'pg_other_owner_$suffix';
      await store.createBusinessOwner(
        businessId: business,
        businessName: 'PG Teste',
        segment: 'salao',
        userId: owner,
        ownerName: 'Dona',
        phone: '5511999999999',
        login: 'pg-$suffix@test.local',
        passwordHash: 'test-only',
      );
      await store.createBusinessOwner(
        businessId: otherBusiness,
        businessName: 'Outro PG',
        segment: 'salao',
        userId: otherOwner,
        ownerName: 'Outra',
        phone: '5511888888888',
        login: 'other-$suffix@test.local',
        passwordHash: 'test-only',
      );
      final actor = AuthContext(
        userId: owner,
        businessId: business,
        role: 'dono',
        sessionId: 'pg-test',
      );
      final otherActor = AuthContext(
        userId: otherOwner,
        businessId: otherBusiness,
        role: 'dono',
        sessionId: 'pg-other-test',
      );
      await store.applyMutations(
        actor: actor,
        mutations: [
          _mutation('servicos', 'service', {
            'id': 'service',
            'nome': 'Serviço',
            'ativo': true,
            'duracao_minutos': 60,
          }),
          _mutation('profissionais', 'professional', {
            'id': 'professional',
            'nome': 'Rafa',
            'ativo': true,
            'unidade_id': 'unit',
          }),
          _mutation('unidades', 'unit', {
            'id': 'unit',
            'nome': 'Centro',
            'ativo': true,
          }),
          _mutation('profissional_servicos', 'link', {
            'id': 'link',
            'profissional_id': 'professional',
            'servico_id': 'service',
          }),
        ],
      );
      await store.applyMutations(
        actor: otherActor,
        mutations: [
          _mutation('servicos', 'service', {
            'id': 'service',
            'nome': 'Serviço',
            'ativo': true,
            'duracao_minutos': 60,
          }),
          _mutation('profissionais', 'professional', {
            'id': 'professional',
            'nome': 'Outra',
            'ativo': true,
            'unidade_id': 'unit',
          }),
          _mutation('unidades', 'unit', {
            'id': 'unit',
            'nome': 'Outra',
            'ativo': true,
          }),
          _mutation('profissional_servicos', 'link', {
            'id': 'link',
            'profissional_id': 'professional',
            'servico_id': 'service',
          }),
          _mutation('clientes', 'existing-other', {
            'id': 'existing-other',
            'nome': 'Mesmo telefone',
            'whatsapp': '5511977777777',
            'ativo': true,
          }),
        ],
      );
      final start = DateTime.now().toUtc().add(const Duration(days: 3));
      Future<PublicAppointment> create(
        String key,
        String hash,
        String token, {
        String businessId = '',
        String phone = '5511977777777',
      }) {
        return store.createPublicAppointment(
          businessId: businessId.isEmpty ? business : businessId,
          idempotencyKey: key,
          tokenHash: hash,
          publicToken: token,
          serviceId: 'service',
          professionalId: 'professional',
          unitId: 'unit',
          clientName: 'Maria',
          clientPhone: phone,
          notes: 'Teste PG',
          startsAt: start,
          endsAt: start.add(const Duration(hours: 1)),
        );
      }

      final created = await create(
        'first-$suffix',
        'hash-first-$suffix',
        'token-first',
      );
      expect(created.status, 'agendado');
      final publicRow = await store.pool.execute(
        Sql.named(
          'SELECT client_id,appointment_id FROM public_appointments WHERE business_id=@business',
        ),
        parameters: {'business': business},
      );
      expect(publicRow, hasLength(1));
      final ids = publicRow.single.toColumnMap();
      expect(ids['client_id'], isNotNull);
      expect(ids['appointment_id'], isNotNull);
      final mainRows = await store.pool.execute(
        Sql.named('''
      SELECT entity,payload FROM sync_records WHERE business_id=@business
        AND entity IN ('clientes','agendamentos')
    '''),
        parameters: {'business': business},
      );
      expect(
        mainRows.where((r) => r.toColumnMap()['entity'] == 'clientes'),
        hasLength(1),
      );
      expect(
        mainRows.where((r) => r.toColumnMap()['entity'] == 'agendamentos'),
        hasLength(1),
      );
      expect(
        await store.pool.execute(
          Sql.named(
            'SELECT 1 FROM sync_changes WHERE business_id=@business AND entity=\'agendamentos\'',
          ),
          parameters: {'business': business},
        ),
        isNotEmpty,
      );
      expect(
        await store.pool.execute(
          Sql.named(
            'SELECT 1 FROM audit_logs WHERE business_id=@business AND event=\'public_booking.created\'',
          ),
          parameters: {'business': business},
        ),
        isNotEmpty,
      );

      final retry = await create(
        'first-$suffix',
        'unused-$suffix',
        'unused-token',
      );
      expect(retry.startsAt, created.startsAt);
      expect(
        await store.pool.execute(
          Sql.named(
            'SELECT 1 FROM public_appointments WHERE business_id=@business',
          ),
          parameters: {'business': business},
        ),
        hasLength(1),
      );

      final samePhoneOther = await create(
        'other-$suffix',
        'hash-other-$suffix',
        'token-other',
        businessId: otherBusiness,
      );
      expect(samePhoneOther.businessId, otherBusiness);
      final otherClient = await store.pool.execute(
        Sql.named('''
      SELECT payload->>'id' id FROM sync_records WHERE business_id=@business
        AND entity='clientes' AND payload->>'whatsapp'='5511977777777'
    '''),
        parameters: {'business': otherBusiness},
      );
      expect(otherClient.single.toColumnMap()['id'], 'existing-other');

      final parallelStart = start.add(const Duration(hours: 3));
      Future<Object> concurrent(String n) async {
        try {
          return await store.createPublicAppointment(
            businessId: business,
            idempotencyKey: 'parallel-$n-$suffix',
            tokenHash: 'parallel-hash-$n-$suffix',
            publicToken: 'parallel-$n',
            serviceId: 'service',
            professionalId: 'professional',
            unitId: 'unit',
            clientName: 'Concorrente $n',
            clientPhone: '55119666666$n',
            startsAt: parallelStart,
            endsAt: parallelStart.add(const Duration(hours: 1)),
          );
        } catch (error) {
          return error;
        }
      }

      final concurrentResults = await Future.wait([
        concurrent('1'),
        concurrent('2'),
      ]);
      expect(concurrentResults.whereType<PublicAppointment>(), hasLength(1));
      expect(concurrentResults.whereType<StateError>(), hasLength(1));

      await store.updatePublicAppointment(
        tokenHash: 'hash-first-$suffix',
        status: 'confirmado',
      );
      expect(
        await _mainStatus(store, business, ids['appointment_id'] as String),
        'confirmado',
      );
      await store.updatePublicAppointment(
        tokenHash: 'hash-first-$suffix',
        status: 'cancelado',
      );
      expect(
        await _mainStatus(store, business, ids['appointment_id'] as String),
        'cancelado',
      );
      final moved = start.add(const Duration(days: 1));
      final rescheduled = await store.updatePublicAppointment(
        tokenHash: 'hash-first-$suffix',
        status: 'reagendado',
        startsAt: moved,
      );
      expect(
        rescheduled!.endsAt.difference(rescheduled.startsAt),
        const Duration(hours: 1),
      );
      expect(
        await _mainStatus(store, business, ids['appointment_id'] as String),
        'reagendado',
      );

      await store.pool.execute('''
      CREATE OR REPLACE FUNCTION fail_public_test() RETURNS trigger LANGUAGE plpgsql AS \$\$
      BEGIN IF NEW.idempotency_key LIKE 'force-rollback-%' THEN
        RAISE EXCEPTION 'forced rollback'; END IF; RETURN NEW; END \$\$;
      CREATE TRIGGER public_test_rollback BEFORE INSERT ON public_appointments
        FOR EACH ROW EXECUTE FUNCTION fail_public_test();
    ''');
      final beforeClients = await _count(store, business, 'clientes');
      final beforeAppointments = await _count(store, business, 'agendamentos');
      await expectLater(
        store.createPublicAppointment(
          businessId: business,
          idempotencyKey: 'force-rollback-$suffix',
          tokenHash: 'rollback-hash-$suffix',
          publicToken: 'rollback-token',
          serviceId: 'service',
          professionalId: 'professional',
          unitId: 'unit',
          clientName: 'Rollback',
          clientPhone: '5511955555555',
          startsAt: start.add(const Duration(hours: 6)),
          endsAt: start.add(const Duration(hours: 7)),
        ),
        throwsA(anything),
      );
      expect(await _count(store, business, 'clientes'), beforeClients);
      expect(await _count(store, business, 'agendamentos'), beforeAppointments);
      await store.pool.execute(
        'DROP TRIGGER public_test_rollback ON public_appointments; DROP FUNCTION fail_public_test();',
      );
    },
    skip: url == null ? 'POSTGRES_TEST_URL não configurada' : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

SyncMutation _mutation(
  String entity,
  String id,
  Map<String, Object?> payload,
) => SyncMutation(
  operationId: '$entity-$id',
  entity: entity,
  entityId: id,
  operation: 'criar',
  localVersion: 0,
  payload: payload,
);

Future<int> _count(
  PostgresBackendStore store,
  String business,
  String entity,
) async {
  final rows = await store.pool.execute(
    Sql.named(
      'SELECT count(*) total FROM sync_records WHERE business_id=@business AND entity=@entity',
    ),
    parameters: {'business': business, 'entity': entity},
  );
  return rows.single.toColumnMap()['total'] as int;
}

Future<String?> _mainStatus(
  PostgresBackendStore store,
  String business,
  String appointment,
) async {
  final rows = await store.pool.execute(
    Sql.named('''
    SELECT payload->>'status' status FROM sync_records
    WHERE business_id=@business AND entity='agendamentos' AND entity_id=@appointment
  '''),
    parameters: {'business': business, 'appointment': appointment},
  );
  return rows.single.toColumnMap()['status'] as String?;
}
