import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../core/utils/id_generator.dart';
import '../database/database_service.dart';
import '../models/domain/acesso.dart';
import '../models/domain/sincronizacao_backend.dart';
import 'backend_api_client.dart';
import 'backend_token_vault.dart';

class BackendSyncService {
  static const _excludedTables = {
    'backups_logicos',
    'fila_sincronizacao',
    'integracoes_configuracao',
    'conflitos_sincronizacao',
    'alteracoes_remotas',
    'registro_sync_estado',
    'sessoes',
    'recuperacoes_senha',
    'dispositivos_sincronizacao',
    'schema_migrations',
  };

  static const _priority = <String>[
    'usuarios',
    'profissionais',
    'clientes',
    'servicos',
    'produtos_estoque',
    'produtos_loja',
    'agendamentos',
    'caixas',
    'vendas',
    'movimentacoes_financeiras',
  ];

  final Future<Database> Function() _databaseProvider;
  final BackendApiClient _api;
  final BackendTokenVault _vault;

  BackendSyncService({
    Future<Database> Function()? databaseProvider,
    BackendApiClient? api,
    BackendTokenVault? vault,
  }) : _databaseProvider =
           databaseProvider ?? (() => DatabaseService.instance.database),
       _api = api ?? BackendApiClient(),
       _vault = vault ?? const SecureBackendTokenVault();

  Future<void> conectar({
    required UsuarioAcesso usuario,
    required CredenciaisBackend credenciais,
    bool criarAmbienteSeAusente = false,
  }) async {
    final endpoint = _api.normalizeEndpoint(credenciais.endpoint);
    Map<String, dynamic> response;
    try {
      response = await _api.login(
        endpoint: endpoint,
        login: credenciais.login,
        password: credenciais.senha,
        businessId: usuario.comercioId,
      );
    } on BackendHttpException {
      rethrow;
    }
    final session = _sessionFromResponse(response, usuario.comercioId);
    if (session.comercioId != usuario.comercioId) {
      throw StateError(
        'O ambiente remoto não corresponde ao comércio selecionado.',
      );
    }
    await _vault.write(session);
    final db = await _databaseProvider();
    await db.update(
      'integracoes_configuracao',
      {
        'provedor_backend': 'studioflow_rest',
        'endpoint_publico': endpoint.toString(),
        'sincronizacao_ativa': 1,
        'ultimo_erro': null,
        'atualizado_em': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'comercio_id = ?',
      whereArgs: [usuario.comercioId],
    );
  }

  Future<Map<String, dynamic>> buscarProdutoGtin(
    String comercioId,
    String gtin,
  ) async {
    final db = await _databaseProvider();
    final rows = await db.query(
      'integracoes_configuracao',
      columns: ['endpoint_publico', 'sincronizacao_ativa'],
      where: 'comercio_id = ?',
      whereArgs: [comercioId],
      limit: 1,
    );
    if (rows.isEmpty || rows.single['sincronizacao_ativa'] != 1) {
      throw StateError(
        'Conecte o backend em Produção e sincronização para consultar o catálogo externo.',
      );
    }
    final endpointText = rows.single['endpoint_publico'] as String?;
    var session = await _vault.read(comercioId);
    if (endpointText == null || session == null) {
      throw StateError(
        'Sessão online indisponível. Entre novamente no backend.',
      );
    }
    final endpoint = _api.normalizeEndpoint(endpointText);
    try {
      return await _api.catalogGtin(
        endpoint: endpoint,
        accessToken: session.accessToken,
        gtin: gtin,
      );
    } on BackendHttpException catch (error) {
      if (error.statusCode != 401) rethrow;
      session = await _refreshSession(endpoint, session);
      return _api.catalogGtin(
        endpoint: endpoint,
        accessToken: session.accessToken,
        gtin: gtin,
      );
    }
  }

  Future<List<Map<String, dynamic>>> historicoMensagens(
    String comercioId, {
    int limit = 100,
  }) async {
    final db = await _databaseProvider();
    final config = await db.query(
      'integracoes_configuracao',
      columns: ['endpoint_publico', 'sincronizacao_ativa'],
      where: 'comercio_id = ?',
      whereArgs: [comercioId],
      limit: 1,
    );
    if (config.isEmpty || config.single['sincronizacao_ativa'] != 1) {
      throw StateError(
        'Conecte o backend em Produção e sincronização para consultar os envios.',
      );
    }
    final endpointText = config.single['endpoint_publico'] as String?;
    final session = await _vault.read(comercioId);
    if (endpointText == null || session == null) {
      throw StateError(
        'Sessão online indisponível. Entre novamente no backend.',
      );
    }
    final response = await _api.messagesHistory(
      endpoint: _api.normalizeEndpoint(endpointText),
      accessToken: session.accessToken,
      limit: limit,
    );
    final items = response['messages'] as List? ?? const [];
    return items
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> desconectar(String comercioId) async {
    await _vault.delete(comercioId);
    final db = await _databaseProvider();
    await db.update(
      'integracoes_configuracao',
      {
        'sincronizacao_ativa': 0,
        'ultimo_erro': null,
        'atualizado_em': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'comercio_id = ?',
      whereArgs: [comercioId],
    );
  }

  Future<ResultadoSincronizacao> sincronizar(String comercioId) async {
    final db = await _databaseProvider();
    final configRows = await db.query(
      'integracoes_configuracao',
      where: 'comercio_id = ? AND sincronizacao_ativa = 1',
      whereArgs: [comercioId],
      limit: 1,
    );
    if (configRows.isEmpty) {
      throw StateError('A sincronização online não está ativada.');
    }
    final endpointText = configRows.single['endpoint_publico'] as String?;
    if (endpointText == null) throw StateError('Endpoint não configurado.');
    final endpoint = _api.normalizeEndpoint(endpointText);
    var session = await _vault.read(comercioId);
    if (session == null) {
      throw StateError('Entre novamente para renovar a sessão online.');
    }

    try {
      await _detectarAlteracoes(db, comercioId);
      final pushResult = await _enviarPendentes(
        db,
        endpoint,
        session,
        comercioId,
      );
      session = pushResult.session;
      final recebidas = await _receberAlteracoes(
        db,
        endpoint,
        session,
        comercioId,
        configRows.single['ultimo_cursor'] as int? ?? 0,
      );
      final pendentes =
          Sqflite.firstIntValue(
            await db.rawQuery(
              "SELECT COUNT(*) FROM fila_sincronizacao "
              "WHERE comercio_id = ? AND status = 'pendente'",
              [comercioId],
            ),
          ) ??
          0;
      await db.update(
        'integracoes_configuracao',
        {
          'ultima_sincronizacao': DateTime.now().toUtc().toIso8601String(),
          'ultimo_erro': null,
          'atualizado_em': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'comercio_id = ?',
        whereArgs: [comercioId],
      );
      return ResultadoSincronizacao(
        enviadas: pushResult.applied,
        recebidas: recebidas,
        conflitos: pushResult.conflicts,
        pendentes: pendentes,
      );
    } on Object catch (error) {
      await db.update(
        'integracoes_configuracao',
        {
          'ultimo_erro': error.toString(),
          'atualizado_em': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'comercio_id = ?',
        whereArgs: [comercioId],
      );
      rethrow;
    }
  }

  Future<void> _detectarAlteracoes(Database db, String comercioId) async {
    final tables = await _syncTables(db);
    final now = DateTime.now().toUtc().toIso8601String();
    for (final table in tables) {
      final rows = await db.query(
        table,
        where: 'comercio_id = ?',
        whereArgs: [comercioId],
      );
      final existingIds = <String>{};
      for (final row in rows) {
        final id = row['id']?.toString();
        if (id == null || id.isEmpty) continue;
        existingIds.add(id);
        final payload = Map<String, Object?>.from(row);
        final hash = _payloadHash(payload);
        final state = await db.query(
          'registro_sync_estado',
          where: 'comercio_id = ? AND entidade = ? AND entidade_id = ?',
          whereArgs: [comercioId, table, id],
          limit: 1,
        );
        if (state.isNotEmpty && state.single['hash_local'] == hash) continue;
        final serverVersion = state.isEmpty
            ? 0
            : state.single['versao_servidor'] as int;
        await _upsertQueue(
          db,
          comercioId: comercioId,
          entity: table,
          entityId: id,
          operation: state.isEmpty ? 'criar' : 'atualizar',
          payload: payload,
          serverVersion: serverVersion,
          now: now,
        );
      }
      final states = await db.query(
        'registro_sync_estado',
        where: 'comercio_id = ? AND entidade = ?',
        whereArgs: [comercioId, table],
      );
      for (final state in states) {
        final entityId = state['entidade_id'] as String;
        if (existingIds.contains(entityId)) continue;
        await _upsertQueue(
          db,
          comercioId: comercioId,
          entity: table,
          entityId: entityId,
          operation: 'excluir',
          payload: const {},
          serverVersion: state['versao_servidor'] as int,
          now: now,
        );
      }
    }
  }

  Future<void> _upsertQueue(
    Database db, {
    required String comercioId,
    required String entity,
    required String entityId,
    required String operation,
    required Map<String, Object?> payload,
    required int serverVersion,
    required String now,
  }) async {
    final pending = await db.query(
      'fila_sincronizacao',
      where:
          "comercio_id = ? AND entidade = ? AND entidade_id = ? "
          "AND status = 'pendente'",
      whereArgs: [comercioId, entity, entityId],
      limit: 1,
    );
    if (pending.isNotEmpty) {
      await db.update(
        'fila_sincronizacao',
        {
          'operacao': operation,
          'payload_json': jsonEncode(payload),
          'versao_servidor': serverVersion,
          'atualizada_em': now,
        },
        where: 'id = ?',
        whereArgs: [pending.single['id']],
      );
      return;
    }
    await db.insert('fila_sincronizacao', {
      'id': 'sync_${IdGenerator.temporal()}',
      'comercio_id': comercioId,
      'entidade': entity,
      'entidade_id': entityId,
      'operacao': operation,
      'payload_json': jsonEncode(payload),
      'versao_local': serverVersion,
      'versao_servidor': serverVersion,
      'status': 'pendente',
      'tentativas': 0,
      'criada_em': now,
      'atualizada_em': now,
    });
  }

  Future<_PushOutcome> _enviarPendentes(
    Database db,
    Uri endpoint,
    SessaoBackend session,
    String comercioId,
  ) async {
    final rows = await db.query(
      'fila_sincronizacao',
      where: "comercio_id = ? AND status = 'pendente'",
      whereArgs: [comercioId],
      orderBy: 'criada_em',
      limit: 100,
    );
    if (rows.isEmpty) return _PushOutcome(session, 0, 0);
    final operations = rows
        .map(
          (row) => <String, Object?>{
            'operationId': row['id'],
            'entity': row['entidade'],
            'entityId': row['entidade_id'],
            'operation': row['operacao'] == 'upsert'
                ? ((row['versao_servidor'] as int? ?? 0) == 0
                      ? 'criar'
                      : 'atualizar')
                : row['operacao'],
            'localVersion': row['versao_servidor'],
            'payload': jsonDecode(row['payload_json'] as String) as Object?,
          },
        )
        .toList();
    Map<String, dynamic> response;
    try {
      response = await _api.push(
        endpoint: endpoint,
        accessToken: session.accessToken,
        operations: operations,
      );
    } on BackendHttpException catch (error) {
      if (error.statusCode != 401) rethrow;
      session = await _refreshSession(endpoint, session);
      response = await _api.push(
        endpoint: endpoint,
        accessToken: session.accessToken,
        operations: operations,
      );
    }
    var applied = 0;
    var conflicts = 0;
    final results = response['results'] as List? ?? const [];
    await db.transaction((txn) async {
      for (final raw in results) {
        final result = Map<String, dynamic>.from(raw as Map);
        final operationId = result['operationId'] as String;
        final row = rows.firstWhere((item) => item['id'] == operationId);
        final version = (result['serverVersion'] as num).toInt();
        if (result['status'] == 'applied') {
          applied++;
          final payload = jsonDecode(row['payload_json'] as String);
          await txn.update(
            'fila_sincronizacao',
            {
              'status': 'sincronizado',
              'versao_servidor': version,
              'sincronizada_em': DateTime.now().toUtc().toIso8601String(),
              'ultimo_erro': null,
              'atualizada_em': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [operationId],
          );
          await txn.insert('registro_sync_estado', {
            'comercio_id': comercioId,
            'entidade': row['entidade'],
            'entidade_id': row['entidade_id'],
            'hash_local': _payloadHash(
              payload is Map ? Map<String, Object?>.from(payload) : const {},
            ),
            'versao_servidor': version,
            'atualizado_em': DateTime.now().toUtc().toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        } else {
          conflicts++;
          await txn.update(
            'fila_sincronizacao',
            {
              'status': 'conflito',
              'versao_servidor': version,
              'ultimo_erro': 'Conflito de versão.',
              'atualizada_em': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [operationId],
          );
          await txn.insert('conflitos_sincronizacao', {
            'id': 'conf_${IdGenerator.temporal()}',
            'comercio_id': comercioId,
            'operacao_id': operationId,
            'entidade': row['entidade'],
            'entidade_id': row['entidade_id'],
            'versao_local': row['versao_servidor'],
            'versao_servidor': version,
            'payload_local': row['payload_json'],
            'payload_servidor': jsonEncode(result['serverPayload']),
            'status': 'pendente',
            'criado_em': DateTime.now().toUtc().toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
    });
    return _PushOutcome(session, applied, conflicts);
  }

  Future<int> _receberAlteracoes(
    Database db,
    Uri endpoint,
    SessaoBackend session,
    String comercioId,
    int cursor,
  ) async {
    Map<String, dynamic> response;
    try {
      response = await _api.pull(
        endpoint: endpoint,
        accessToken: session.accessToken,
        cursor: cursor,
      );
    } on BackendHttpException catch (error) {
      if (error.statusCode != 401) rethrow;
      session = await _refreshSession(endpoint, session);
      response = await _api.pull(
        endpoint: endpoint,
        accessToken: session.accessToken,
        cursor: cursor,
      );
    }
    final changes = response['changes'] as List? ?? const [];
    if (changes.isEmpty) return 0;
    final tables = (await _syncTables(db)).toSet();
    var applied = 0;
    var lastCursor = cursor;
    for (final raw in changes) {
      final change = Map<String, dynamic>.from(raw as Map);
      final changeCursor = (change['cursor'] as num).toInt();
      final entity = change['entity'] as String;
      final entityId = change['entityId'] as String;
      final payload = Map<String, Object?>.from(
        change['payload'] as Map? ?? const {},
      );
      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert('alteracoes_remotas', {
        'comercio_id': comercioId,
        'cursor': changeCursor,
        'entidade': entity,
        'entidade_id': entityId,
        'versao_servidor': change['serverVersion'],
        'excluido': change['deleted'] == true ? 1 : 0,
        'payload_json': jsonEncode(payload),
        'recebido_em': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      if (!tables.contains(entity)) {
        await db.update(
          'alteracoes_remotas',
          {'erro': 'Entidade não permitida.'},
          where: 'comercio_id = ? AND cursor = ?',
          whereArgs: [comercioId, changeCursor],
        );
        lastCursor = changeCursor;
        continue;
      }
      try {
        await _applyRemote(
          db,
          comercioId: comercioId,
          entity: entity,
          entityId: entityId,
          payload: payload,
          deleted: change['deleted'] == true,
          serverVersion: (change['serverVersion'] as num).toInt(),
        );
        await db.update(
          'alteracoes_remotas',
          {'aplicado_em': now, 'erro': null},
          where: 'comercio_id = ? AND cursor = ?',
          whereArgs: [comercioId, changeCursor],
        );
        lastCursor = changeCursor;
        applied++;
      } on Object catch (error) {
        await db.update(
          'alteracoes_remotas',
          {'erro': error.toString()},
          where: 'comercio_id = ? AND cursor = ?',
          whereArgs: [comercioId, changeCursor],
        );
        break;
      }
    }
    await db.update(
      'integracoes_configuracao',
      {'ultimo_cursor': lastCursor},
      where: 'comercio_id = ?',
      whereArgs: [comercioId],
    );
    return applied;
  }

  Future<void> _applyRemote(
    Database db, {
    required String comercioId,
    required String entity,
    required String entityId,
    required Map<String, Object?> payload,
    required bool deleted,
    required int serverVersion,
  }) async {
    final columns = await db.rawQuery('PRAGMA table_info($entity)');
    final allowed = columns.map((column) => column['name'] as String).toSet();
    if (!allowed.containsAll(const {'id', 'comercio_id'})) {
      throw StateError('Tabela sem isolamento multiempresa.');
    }
    if (deleted) {
      await db.delete(
        entity,
        where: 'id = ? AND comercio_id = ?',
        whereArgs: [entityId, comercioId],
      );
      await db.delete(
        'registro_sync_estado',
        where: 'comercio_id = ? AND entidade = ? AND entidade_id = ?',
        whereArgs: [comercioId, entity, entityId],
      );
      return;
    }
    final safe = <String, Object?>{
      for (final entry in payload.entries)
        if (allowed.contains(entry.key)) entry.key: entry.value,
      'id': entityId,
      'comercio_id': comercioId,
    };
    final updated = await db.update(
      entity,
      safe,
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [entityId, comercioId],
    );
    if (updated == 0) await db.insert(entity, safe);
    await db.insert('registro_sync_estado', {
      'comercio_id': comercioId,
      'entidade': entity,
      'entidade_id': entityId,
      'hash_local': _payloadHash(safe),
      'versao_servidor': serverVersion,
      'atualizado_em': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<String>> _syncTables(Database db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name NOT LIKE 'sqlite_%'",
    );
    final result = <String>[];
    for (final row in rows) {
      final name = row['name'] as String;
      if (_excludedTables.contains(name) ||
          !RegExp(r'^[A-Za-z0-9_]+$').hasMatch(name)) {
        continue;
      }
      final columns = await db.rawQuery('PRAGMA table_info($name)');
      final names = columns.map((column) => column['name']).toSet();
      if (names.contains('id') && names.contains('comercio_id')) {
        result.add(name);
      }
    }
    result.sort((a, b) {
      final ai = _priority.indexOf(a);
      final bi = _priority.indexOf(b);
      if (ai >= 0 || bi >= 0) {
        return (ai < 0 ? 999 : ai).compareTo(bi < 0 ? 999 : bi);
      }
      return a.compareTo(b);
    });
    return result;
  }

  Future<SessaoBackend> _refreshSession(
    Uri endpoint,
    SessaoBackend session,
  ) async {
    if (!session.refreshExpiraEm.isAfter(DateTime.now().toUtc())) {
      throw StateError('A sessão online expirou. Entre novamente.');
    }
    final response = await _api.refresh(
      endpoint: endpoint,
      refreshToken: session.refreshToken,
    );
    final updated = SessaoBackend(
      comercioId: session.comercioId,
      usuarioId: session.usuarioId,
      accessToken: response['accessToken'] as String,
      refreshToken: response['refreshToken'] as String,
      refreshExpiraEm: DateTime.parse(
        response['refreshTokenExpiresAt'] as String,
      ),
    );
    await _vault.write(updated);
    return updated;
  }

  SessaoBackend _sessionFromResponse(
    Map<String, dynamic> response,
    String expectedBusinessId,
  ) {
    if (response['selectionRequired'] == true) {
      throw StateError('Selecione o comércio correspondente no login online.');
    }
    final account = Map<String, dynamic>.from(response['account'] as Map);
    return SessaoBackend(
      comercioId: account['businessId'] as String,
      usuarioId: account['userId'] as String,
      accessToken: response['accessToken'] as String,
      refreshToken: response['refreshToken'] as String,
      refreshExpiraEm: DateTime.parse(
        response['refreshTokenExpiresAt'] as String,
      ),
    );
  }

  static String _payloadHash(Map<String, Object?> payload) {
    final sorted = Map<String, Object?>.fromEntries(
      payload.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    return sha256.convert(utf8.encode(jsonEncode(sorted))).toString();
  }
}

class _PushOutcome {
  final SessaoBackend session;
  final int applied;
  final int conflicts;

  const _PushOutcome(this.session, this.applied, this.conflicts);
}
