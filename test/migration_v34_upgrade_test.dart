import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/migrations/migration_v34.dart';
import 'package:studioflow/repositories/whatsapp_fila_repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'Upgrade V33 -> V34 preserva colunas legadas e injeta as novas, mantendo compatibilidade',
    () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);

      // 1. Simular Schema antigo do whatsapp_fila (V6)
      await db.execute('''
      CREATE TABLE whatsapp_fila (
        id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL, destinatario TEXT NOT NULL,
        template TEXT, payload_json TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'simulado',
        criado_em TEXT NOT NULL, atualizado_em TEXT NOT NULL
      )
    ''');

      // Simular que agendamentos existia sem as novas colunas
      await db.execute('''
      CREATE TABLE agendamentos (
        id TEXT PRIMARY KEY,
        comercio_id TEXT NOT NULL,
        cliente_id TEXT NOT NULL,
        profissional_id TEXT NOT NULL,
        servico_id TEXT NOT NULL,
        inicio TEXT NOT NULL,
        fim TEXT NOT NULL,
        status TEXT NOT NULL,
        valor_servico REAL NOT NULL,
        data_criacao TEXT NOT NULL
      )
    ''');

      await db.execute(
        'CREATE TABLE clientes (id TEXT PRIMARY KEY, nome TEXT NOT NULL, whatsapp TEXT NOT NULL)',
      );
      await db.execute(
        'CREATE TABLE profissionais (id TEXT PRIMARY KEY, nome TEXT NOT NULL, whatsapp TEXT NOT NULL, cargo TEXT NOT NULL)',
      );
      await db.execute(
        'CREATE TABLE servicos (id TEXT PRIMARY KEY, nome TEXT NOT NULL, categoria TEXT NOT NULL, preco REAL NOT NULL, duracao_minutos INTEGER NOT NULL)',
      );

      await db.insert('clientes', {
        'id': 'cli_1',
        'nome': 'Cliente',
        'whatsapp': '11999999999',
      });
      await db.insert('profissionais', {
        'id': 'pro_1',
        'nome': 'Pro',
        'whatsapp': '11999999999',
        'cargo': 'cabeleireiro',
      });
      await db.insert('servicos', {
        'id': 'ser_1',
        'nome': 'Corte',
        'categoria': 'cabelo',
        'preco': 50,
        'duracao_minutos': 30,
      });

      // Inserir dados legados na whatsapp_fila
      await db.insert('whatsapp_fila', {
        'id': 'msg_1',
        'comercio_id': 'com_123',
        'destinatario': '11999999999',
        'template': 'boas_vindas',
        'payload_json': '{}',
        'status': 'simulado',
        'criado_em': '2023-01-01T00:00:00Z',
        'atualizado_em': '2023-01-01T00:00:00Z',
      });

      // Executar migraÃ§Ã£o
      await MigrationV34.executar(db);

      // Validar se creditos_comerciais existe
      final colsCreditos = await db.rawQuery(
        'PRAGMA table_info(creditos_comerciais)',
      );
      expect(colsCreditos.isNotEmpty, isTrue);

      // Validar whatsapp_fila
      final colsFila = await db.rawQuery('PRAGMA table_info(whatsapp_fila)');
      expect(colsFila.any((c) => c['name'] == 'business_id'), isTrue);
      expect(
        colsFila.any((c) => c['name'] == 'comercio_id'),
        isTrue,
      ); // Permanece!
      expect(colsFila.any((c) => c['name'] == 'agendamento_id'), isTrue);

      // Verificar backfill
      final filaQuery = await db.query('whatsapp_fila');
      expect(filaQuery.first['business_id'], 'com_123'); // Foi backfilled
      expect(filaQuery.first['created_at'], '2023-01-01T00:00:00Z');
      expect(filaQuery.first['payload'], '{}');
      expect(filaQuery.first['template_id'], 'boas_vindas');

      // Mock do DatabaseService
      // Ou simplesmente ignoramos a criaÃ§Ã£o limpa do repositorio jÃ¡ que a dependÃªncia Ã© sÃ³ o _comercioId
      // Vamos usar db.insert diretamente para testar o DTO do whatsapp fila em vez de mockar tudo
      // ou apenas testar consultas.
      //
      // Como a Migration garantiu o schema, qualquer repo usando db.insert/update com os modelos atuais vai passar
      final wppRepo = WhatsappFilaRepository(
        databaseProvider: () async => db,
        comercioId: 'com_123',
      );

      final msgs = await wppRepo.consultarFila();

      // A legada deve conseguir ser convertida
      expect(msgs.length, 1);
      expect(msgs.first.businessId, 'com_123');

      // Inserir via repositório validando se o DTO consegue satisfazer schema legado e novo
      await wppRepo.enfileirarMensagem(
        destinatario: '11988888888',
        agendamentoId: 'ag_123',
        payload: '{}',
      );
      final msgsAtualizadas = await wppRepo.consultarFila();
      expect(msgsAtualizadas.length, 2);

      await db.close();
    },
  );
}
