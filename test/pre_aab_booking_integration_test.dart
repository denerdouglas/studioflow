import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/core/utils/id_generator.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/repositories/acesso_repository.dart';
import 'package:studioflow/repositories/agenda_repository.dart';
import 'package:studioflow/repositories/booking_settings_repository.dart';
import 'package:studioflow/services/session_controller.dart';
import 'package:studioflow/database/database_service.dart';

class MockDatabaseService implements DatabaseService {
  final Database _db;
  MockDatabaseService(this._db);

  @override
  Future<Database> get database async => _db;

  @override
  Future<void> fecharBanco() async {}

  @override
  Future<void> limparBanco() async {}
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'Garante o fluxo do backend para o agendamento público (Erro 3)',
    () async {
      final db = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 37,
          onCreate: DatabaseSchemaLatest.criar,
          onConfigure: (db) async =>
              await db.execute('PRAGMA foreign_keys = ON'),
        ),
      );

      final businessId = 'com_123456';
      final userId = 'usr_123456';

      // 1. Simula login recebendo account identity do PostgreSQL
      final acessoRepo = AcessoRepository(databaseProvider: () async => db);
      final accountPayload = {
        'businessId': businessId,
        'userId': userId,
        'businessName': 'Dener Testando',
        'userName': 'Dener',
        'phone': '11999999999',
        'login': 'dener@test.com',
        'role': 'owner',
        'bookingSlug': 'dener-testando',
        'bookingEnabled': true,
      };

      final usuario = await acessoRepo.restaurarContaOnline(
        account: accountPayload,
        senhaValidada: 'Senha123',
        endpoint: 'https://api.studioflowapp.com.br',
      );

      // Injeta na sessão (necessário para Repositories)
      SessionController.instance.entrar(usuario);

      // 2. Confirma que o SQLite salvou 'dener-testando'
      final comercios = await db.query(
        'comercios',
        where: 'id = ?',
        whereArgs: [businessId],
      );
      expect(comercios.first['booking_slug'], 'dener-testando');
      expect(comercios.first['booking_enabled'], 1);

      // 3. Verifica que a tela carregará 'dener-testando'
      final bookingRepo = BookingSettingsRepository(
        databaseProvider: () async => db,
      );
      final settings = await bookingRepo.load();
      expect(settings.slug, 'dener-testando');
      expect(settings.enabled, true);

      // Confirma que não houve geração fantasma (tabela comercios continua igual)
      final aliases = await db.query('booking_slug_aliases');
      expect(aliases.isEmpty, true);

      // 4. Cria agendamento local simulando o que o _applyRemote faria
      final clienteId = 'cli_${IdGenerator.temporal()}';
      final profissionalId = 'pro_${IdGenerator.temporal()}';
      final servicoId = 'srv_${IdGenerator.temporal()}';

      await db.insert('clientes', {
        'id': clienteId,
        'comercio_id': businessId,
        'nome': 'Cliente Online',
        'whatsapp': '11988888888',
        'data_cadastro': DateTime.now().toIso8601String(),
      });

      await db.insert('profissionais', {
        'id': profissionalId,
        'comercio_id': businessId,
        'nome': 'Profissional Teste',
        'whatsapp': '11988888888',
        'cargo': 'Especialista',
        'ativo': 1,
        'data_cadastro': DateTime.now().toIso8601String(),
      });

      await db.insert('servicos', {
        'id': servicoId,
        'comercio_id': businessId,
        'nome': 'Corte',
        'categoria': 'Geral',
        'preco': 50.0,
        'duracao_minutos': 30,
        'ativo': 1,
        'data_cadastro': DateTime.now().toIso8601String(),
      });

      final inicio = DateTime(2026, 8, 15, 14, 0);
      final fim = inicio.add(const Duration(minutes: 30));
      final agendamentoId = 'age_${IdGenerator.temporal()}';

      // Payload idêntico ao que o _applyRemote salva
      await db.insert('agendamentos', {
        'id': agendamentoId,
        'comercio_id': businessId,
        'cliente_id': clienteId,
        'profissional_id': profissionalId,
        'servico_id': servicoId,
        'status': 'pendente',
        'inicio': inicio.toUtc().toIso8601String(),
        'fim': fim.toUtc().toIso8601String(),
        'valor_servico': 50.0,
        'origem': 'online',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'data_criacao': DateTime.now().toUtc().toIso8601String(),
      });

      // 5. O AgendaRepository consegue enxergar o agendamento?
      final agendaRepo = AgendaRepository(
        databaseService: MockDatabaseService(db),
      );
      final dia = DateTime(2026, 8, 15);
      final agendamentosDia = await agendaRepo.listarPorDia(dia);

      expect(agendamentosDia.length, 1);
      expect(agendamentosDia.first.id, agendamentoId);
      expect(agendamentosDia.first.clienteNome, 'Cliente Online');

      await db.close();
    },
  );
}
