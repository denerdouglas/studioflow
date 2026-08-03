import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:studioflow_backend/studioflow_backend.dart';
import 'package:studioflow_backend/src/academy_memory_store.dart';
import 'package:test/test.dart';

void main() {
  test(
    'disponibilidade usa jornada, duração, ocupação, intervalo e bloqueios',
    () async {
      final store = MemoryBackendStore();
      final config = BackendConfig.fromEnvironment(const {
        'DATABASE_URL': 'postgresql://unused/test',
        'JWT_SECRET':
            '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        'PUBLIC_BASE_URL': 'https://api.studioflow.test',
      });
      final handler = StudioFlowApi(
        store: store,
        marketplace: MarketplaceService(store),
        adminService: MarketplaceAdminService(store),
        academy: AcademyService(AcademyMemoryStore()),
        secureRedirect: SecureRedirectService(AcademyMemoryStore()),
        config: config,
      ).handler;
      final registration = await _jsonCall(
        handler,
        'POST',
        '/v1/auth/register-business',
        body: {
          'businessName': 'Agenda Real',
          'ownerName': 'Dona',
          'phone': '5511999999999',
          'login': 'agenda@studio.test',
          'password': 'senha-segura',
        },
      );
      final account = registration.body['account'] as Map;
      final businessId = account['businessId'] as String;
      final actor = AuthContext(
        userId: account['userId'] as String,
        businessId: businessId,
        role: 'dono',
        sessionId: 'test',
      );
      final date = DateTime.now().add(const Duration(days: 7));
      final day = DateTime(date.year, date.month, date.day);
      String at(int hour, [int minute = 0]) => DateTime(
        day.year,
        day.month,
        day.day,
        hour,
        minute,
      ).toIso8601String();
      await store.applyMutations(
        actor: actor,
        mutations: [
          _mutation('servicos', 's30', {
            'id': 's30',
            'nome': 'Rápido',
            'ativo': true,
            'duracao_minutos': 30,
          }),
          _mutation('servicos', 's60', {
            'id': 's60',
            'nome': 'Longo',
            'ativo': true,
            'duracao_minutos': 60,
          }),
          _mutation('profissionais', 'p1', {
            'id': 'p1',
            'nome': 'Rafa',
            'ativo': true,
            'unidade_id': 'u1',
          }),
          _mutation('profissional_servicos', 'ps30', {
            'id': 'ps30',
            'profissional_id': 'p1',
            'servico_id': 's30',
          }),
          _mutation('profissional_servicos', 'ps60', {
            'id': 'ps60',
            'profissional_id': 'p1',
            'servico_id': 's60',
          }),
          _mutation('horarios_profissionais', 'h1', {
            'id': 'h1',
            'profissional_id': 'p1',
            'unidade_id': 'u1',
            'dia_semana': day.weekday,
            'hora_inicio': '09:00',
            'hora_fim': '12:00',
            'intervalo_inicio': '10:00',
            'intervalo_fim': '10:30',
          }),
        ],
      );
      final empty = await _availability(handler, day, 's30');
      expect(empty, containsAll([at(9), at(9, 30), at(10, 30), at(11, 30)]));

      await store.applyMutations(
        actor: actor,
        mutations: [
          _mutation('agendamentos', 'a1', {
            'id': 'a1',
            'profissional_id': 'p1',
            'unidade_id': 'u1',
            'inicio': at(9, 30),
            'fim': at(10),
            'status': 'agendado',
          }),
          _mutation('bloqueios_agenda', 'b1', {
            'id': 'b1',
            'profissional_id': 'p1',
            'unidade_id': 'u1',
            'inicio': at(11),
            'fim': at(11, 30),
          }),
          _mutation('bloqueios_agenda', 'outro', {
            'id': 'outro',
            'profissional_id': 'p1',
            'unidade_id': 'u2',
            'inicio': at(10, 30),
            'fim': at(11),
          }),
        ],
      );
      final partial = await _availability(handler, day, 's30');
      expect(partial, contains(at(10, 30)));
      expect(partial, isNot(contains(at(9, 30))));
      expect(partial, isNot(contains(at(10))));
      expect(partial, isNot(contains(at(11))));
      final long = await _availability(handler, day, 's60');
      expect(long, isNot(contains(at(9, 30))));
      expect(long, isNot(contains(at(10, 30))));

      await store.applyMutations(
        actor: actor,
        mutations: [
          _mutation('folgas_profissionais', 'f1', {
            'id': 'f1',
            'profissional_id': 'p1',
            'inicio': at(0),
            'fim': at(23, 59),
          }),
        ],
      );
      expect(await _availability(handler, day, 's30'), isEmpty);
    },
  );
}

SyncMutation _mutation(
  String entity,
  String id,
  Map<String, Object?> payload,
) => SyncMutation(
  operationId: 'op-$id',
  entity: entity,
  entityId: id,
  operation: 'criar',
  localVersion: 0,
  payload: payload,
);

Future<List<String>> _availability(
  Handler handler,
  DateTime date,
  String service,
) async {
  final value = date.toIso8601String().split('T').first;
  final result = await _jsonCall(
    handler,
    'GET',
    '/v1/public/booking/agenda-real/availability?date=$value&serviceId=$service&professionalId=p1&unitId=u1',
  );
  expect(result.status, 200);
  return List<String>.from(result.body['slots'] as List);
}

Future<({int status, Map<String, dynamic> body})> _jsonCall(
  Handler handler,
  String method,
  String path, {
  Map<String, Object?>? body,
}) async {
  final response = await handler(
    Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: {if (body != null) 'content-type': 'application/json'},
      body: body == null ? null : jsonEncode(body),
    ),
  );
  return (
    status: response.statusCode,
    body: Map<String, dynamic>.from(
      jsonDecode(await response.readAsString()) as Map,
    ),
  );
}
