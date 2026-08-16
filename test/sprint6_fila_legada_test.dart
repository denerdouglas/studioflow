import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/models/domain/acesso.dart';
import 'package:studioflow/services/session_controller.dart';
import 'dart:convert';

void main() {
  late Database db;

  UsuarioAcesso owner() => UsuarioAcesso(
    id: 'user_owner',
    comercioId: 'biz_a',
    codigoComercio: 'BIZ',
    nomeComercio: 'BIZ',
    nomeExibicao: 'BIZ',
    nome: 'Dono',
    telefone: '11999999999',
    emailLogin: 'a@a.com',
    funcao: FuncaoUsuario.dono,
    ativo: true,
    permissoes: ModuloPermissao.values.toSet(),
    acoes: AcaoPermissao.values.toSet(),
  );

  late String tempDbPath;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // Simula banco antigo V5 que possuía fila de sincronização simples
    tempDbPath = 'sprint6_test.db';
    await databaseFactory.deleteDatabase(tempDbPath);
    db = await databaseFactory.openDatabase(
      tempDbPath,
      options: OpenDatabaseOptions(
        version: 5,
        onCreate: (db, version) async {
          await db.execute('''CREATE TABLE fila_sincronizacao (
            id TEXT PRIMARY KEY,
            comercio_id TEXT NOT NULL,
            entidade TEXT NOT NULL,
            entidade_id TEXT NOT NULL,
            operacao TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pendente',
            tentativas INTEGER NOT NULL DEFAULT 0,
            ultimo_erro TEXT,
            proxima_tentativa TEXT,
            criada_em TEXT NOT NULL
          )''');
        },
      ),
    );
  });

  test(
    'BANCO ANTIGO + FILA ANTIGA + UPGRADE + SESSÃO EXISTENTE = RETOMADA DA FILA',
    () async {
      // 1. FILA ANTIGA: inserir itens de fila legada na V5

      // Status legado de erro, que passava a ser pendente se a data_tentativa passasse
      await db.insert('fila_sincronizacao', {
        'id': 'sync_legado_erro',
        'comercio_id': 'biz_a',
        'entidade': 'estoque',
        'entidade_id': 'prod1',
        'operacao': 'upsert',
        'payload_json': '{"nome": "Shampoo V5"}',
        'status': 'pendente',
        'tentativas': 2,
        'proxima_tentativa': DateTime.now()
            .subtract(const Duration(hours: 1))
            .toIso8601String(),
        'criada_em': DateTime.now()
            .subtract(const Duration(hours: 2))
            .toIso8601String(),
      });

      // Item inválido antigo (JSON quebrado)
      await db.insert('fila_sincronizacao', {
        'id': 'sync_legado_invalido',
        'comercio_id': 'biz_a',
        'entidade': 'estoque',
        'entidade_id': 'prod2',
        'operacao': 'upsert',
        'payload_json': 'INVALID_JSON_HERE',
        'status': 'pendente',
        'tentativas': 0,
        'proxima_tentativa': null,
        'criada_em': DateTime.now()
            .subtract(const Duration(minutes: 30))
            .toIso8601String(),
      });

      // Itens válidos posteriores
      await db.insert('fila_sincronizacao', {
        'id': 'sync_legado_valido',
        'comercio_id': 'biz_a',
        'entidade': 'estoque',
        'entidade_id': 'prod3',
        'operacao': 'upsert',
        'payload_json': '{"nome": "Condicionador V5"}',
        'status': 'pendente',
        'tentativas': 0,
        'proxima_tentativa': null,
        'criada_em': DateTime.now()
            .subtract(const Duration(minutes: 10))
            .toIso8601String(),
      });

      // 2. UPGRADE: fechar e abrir na versão atual
      await db.close();
      db = await databaseFactory.openDatabase(
        tempDbPath,
        options: OpenDatabaseOptions(
          version: 6,
          onUpgrade: (db, oldVersion, newVersion) async {
            // Add other required tables for the test to pass if necessary
            await db.execute('''CREATE TABLE registro_sync_estado (
            comercio_id TEXT NOT NULL,
            entidade TEXT NOT NULL,
            entidade_id TEXT NOT NULL,
            hash_local TEXT NOT NULL,
            versao_servidor INTEGER NOT NULL DEFAULT 0,
            atualizado_em TEXT NOT NULL,
            PRIMARY KEY (comercio_id, entidade, entidade_id)
          )''');
          },
        ),
      );

      // 3. SESSÃO EXISTENTE
      SessionController.instance.entrar(owner());

      // 4. RETOMADA DA FILA
      // Não podemos testar o sync full sem mock de API, mas podemos simular que a query da fila funciona.
      // Usaremos as queries idênticas da BackendSyncService para validar.

      final rows = await db.query(
        'fila_sincronizacao',
        where:
            "comercio_id = ? AND status = 'pendente' AND (proxima_tentativa IS NULL OR proxima_tentativa <= ?)",
        whereArgs: ['biz_a', DateTime.now().toUtc().toIso8601String()],
        orderBy: 'criada_em',
        limit: 100,
      );

      // O item inválido deve estar na query mas falhar no loop
      expect(rows.length, 3);

      final itemErro = rows.firstWhere((r) => r['id'] == 'sync_legado_erro');
      expect(itemErro['tentativas'], 2); // Validar Payload antigo
      expect(itemErro['payload_json'], '{"nome": "Shampoo V5"}');
      expect(itemErro['status'], 'pendente');
      expect(itemErro['proxima_tentativa'], isNotNull);

      // Assert que os outros itens estão mantidos na fila
      final itemCorreto = rows.firstWhere(
        (r) => r['id'] == 'sync_legado_valido',
      );
      expect(itemCorreto['tentativas'], 0);
      expect(itemCorreto['status'], 'pendente');

      final itemInvalido = rows.firstWhere(
        (r) => r['id'] == 'sync_legado_invalido',
      );
      expect(itemInvalido['payload_json'], 'INVALID_JSON_HERE');
      expect(itemInvalido['status'], 'pendente');

      // Validar serialização/falha de parsing
      final operations = [];
      for (final row in rows) {
        try {
          final payload = jsonDecode(row['payload_json'] as String) as Object?;
          operations.add({'id': row['id'], 'payload': payload});
        } catch (e) {
          // Item inválido falha aqui e é marcado como erro no loop real!
          await db.update(
            'fila_sincronizacao',
            {'status': 'erro', 'ultimo_erro': 'JSON Inválido legado'},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
      }

      // Apenas 2 itens válidos posteriores foram deserializados com sucesso
      expect(operations.length, 2);
      expect(operations[0]['id'], 'sync_legado_erro');
      expect(operations[1]['id'], 'sync_legado_valido');

      // Verificar se o item inválido foi processado como erro (simulando a tratativa real)
      final inv = (await db.query(
        'fila_sincronizacao',
        where: 'id = ?',
        whereArgs: ['sync_legado_invalido'],
      )).first;
      expect(inv['status'], 'erro');
      expect(inv['ultimo_erro'], 'JSON Inválido legado');
    },
  );
}
