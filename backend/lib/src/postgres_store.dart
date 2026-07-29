import 'dart:convert';

import 'package:postgres/postgres.dart';

import 'models.dart';
import 'store.dart';

final class PostgresBackendStore implements BackendStore {
  final Pool _pool;

  PostgresBackendStore._(this._pool);

  factory PostgresBackendStore.fromUrl(String databaseUrl) {
    return PostgresBackendStore._(Pool.withUrl(databaseUrl));
  }

  @override
  Future<void> ping() async => _pool.execute('SELECT 1');

  @override
  Future<AccountIdentity> createBusinessOwner({
    required String businessId,
    required String businessName,
    required String segment,
    required String userId,
    required String ownerName,
    required String phone,
    required String login,
    required String passwordHash,
  }) {
    return _pool.runTx((tx) async {
      await _setTenant(tx, businessId);
      await tx.execute(
        Sql.named('''
          INSERT INTO businesses (id, name, display_name, segment)
          VALUES (@id, @name, @name, @segment)
        '''),
        parameters: {
          'id': businessId,
          'name': businessName,
          'segment': segment,
        },
      );
      final result = await tx.execute(
        Sql.named('''
          INSERT INTO users
            (id, business_id, name, phone, login, password_hash, role)
          VALUES
            (@id, @businessId, @name, @phone, @login, @passwordHash, 'dono')
          RETURNING id, business_id, name, phone, login, password_hash,
                    role, active
        '''),
        parameters: {
          'id': userId,
          'businessId': businessId,
          'name': ownerName,
          'phone': phone,
          'login': login,
          'passwordHash': passwordHash,
        },
      );
      return _accountFromRow(result.single.toColumnMap(), businessName);
    });
  }

  @override
  Future<List<AccountIdentity>> findAccountsByLogin(String normalizedLogin) {
    return _pool.runTx((tx) async {
      await _allowAuthLookup(tx);
      final result = await tx.execute(
        Sql.named('''
          SELECT u.id, u.business_id, b.display_name AS business_name,
                 u.name, u.phone, u.login, u.password_hash, u.role, u.active
          FROM users u
          INNER JOIN businesses b ON b.id = u.business_id
          WHERE lower(u.login) = @login
            AND u.active = TRUE AND b.active = TRUE
          ORDER BY b.display_name
        '''),
        parameters: {'login': normalizedLogin},
      );
      return result.map((row) => _accountFromRow(row.toColumnMap())).toList();
    });
  }

  @override
  Future<AccountIdentity?> findAccount(String userId, String businessId) {
    return _pool.runTx((tx) async {
      await _setTenant(tx, businessId);
      final result = await tx.execute(
        Sql.named('''
          SELECT u.id, u.business_id, b.display_name AS business_name,
                 u.name, u.phone, u.login, u.password_hash, u.role, u.active
          FROM users u
          INNER JOIN businesses b ON b.id = u.business_id
          WHERE u.id = @userId AND u.business_id = @businessId
        '''),
        parameters: {'userId': userId, 'businessId': businessId},
      );
      return result.isEmpty
          ? null
          : _accountFromRow(result.single.toColumnMap());
    });
  }

  @override
  Future<void> createSession(SessionRecord session) {
    return _pool.runTx((tx) async {
      await _setTenant(tx, session.businessId);
      await tx.execute(
        Sql.named('''
          INSERT INTO sessions
            (id, user_id, business_id, refresh_token_hash, expires_at)
          VALUES (@id, @userId, @businessId, @hash, @expiresAt)
        '''),
        parameters: {
          'id': session.id,
          'userId': session.userId,
          'businessId': session.businessId,
          'hash': session.refreshTokenHash,
          'expiresAt': session.expiresAt,
        },
      );
    });
  }

  @override
  Future<SessionRecord?> findSessionByRefreshHash(String refreshHash) {
    return _pool.runTx((tx) async {
      await _allowAuthLookup(tx);
      final result = await tx.execute(
        Sql.named('''
          SELECT id, user_id, business_id, refresh_token_hash, expires_at,
                 revoked_at IS NOT NULL AS revoked
          FROM sessions WHERE refresh_token_hash = @hash LIMIT 1
        '''),
        parameters: {'hash': refreshHash},
      );
      if (result.isEmpty) return null;
      final row = result.single.toColumnMap();
      return SessionRecord(
        id: row['id'] as String,
        userId: row['user_id'] as String,
        businessId: row['business_id'] as String,
        refreshTokenHash: row['refresh_token_hash'] as String,
        expiresAt: row['expires_at'] as DateTime,
        revoked: row['revoked'] as bool,
      );
    });
  }

  @override
  Future<void> rotateSession({
    required String sessionId,
    required String refreshHash,
    required DateTime expiresAt,
  }) {
    return _pool.runTx((tx) async {
      await _allowAuthLookup(tx);
      await tx.execute(
        Sql.named('''
          UPDATE sessions
          SET refresh_token_hash = @hash, expires_at = @expiresAt,
              last_used_at = now()
          WHERE id = @id AND revoked_at IS NULL
        '''),
        parameters: {
          'id': sessionId,
          'hash': refreshHash,
          'expiresAt': expiresAt,
        },
      );
    });
  }

  @override
  Future<void> revokeSession(String sessionId) {
    return _pool.runTx((tx) async {
      await _allowAuthLookup(tx);
      await tx.execute(
        Sql.named('''
          UPDATE sessions SET revoked_at = now()
          WHERE id = @id AND revoked_at IS NULL
        '''),
        parameters: {'id': sessionId},
      );
    });
  }

  @override
  Future<void> audit({
    required String event,
    String? businessId,
    String? userId,
    String? sessionId,
    required bool success,
    required Map<String, Object?> details,
  }) async {
    await _pool.execute(
      Sql.named('''
        INSERT INTO audit_logs
          (event, business_id, user_id, session_id, success, details)
        VALUES
          (@event, @businessId, @userId, @sessionId, @success,
           CAST(@details AS jsonb))
      '''),
      parameters: {
        'event': event,
        'businessId': businessId,
        'userId': userId,
        'sessionId': sessionId,
        'success': success,
        'details': jsonEncode(details),
      },
    );
  }

  @override
  Future<List<SyncResult>> applyMutations({
    required AuthContext actor,
    required List<SyncMutation> mutations,
  }) {
    return _pool.runTx((tx) async {
      await _setTenant(tx, actor.businessId);
      final results = <SyncResult>[];
      for (final mutation in mutations) {
        results.add(await _applyMutation(tx, actor, mutation));
      }
      return results;
    });
  }

  static Future<SyncResult> _applyMutation(
    Session tx,
    AuthContext actor,
    SyncMutation mutation,
  ) async {
    final previous = await tx.execute(
      Sql.named('''
        SELECT status, server_version, server_payload
        FROM sync_operations
        WHERE operation_id = @operationId AND business_id = @businessId
      '''),
      parameters: {
        'operationId': mutation.operationId,
        'businessId': actor.businessId,
      },
    );
    if (previous.isNotEmpty) {
      final row = previous.single.toColumnMap();
      return SyncResult(
        operationId: mutation.operationId,
        status: row['status'] as String,
        serverVersion: row['server_version'] as int,
        serverPayload: _jsonMap(row['server_payload']),
      );
    }

    final currentResult = await tx.execute(
      Sql.named('''
        SELECT server_version, payload
        FROM sync_records
        WHERE business_id = @businessId
          AND entity = @entity AND entity_id = @entityId
        FOR UPDATE
      '''),
      parameters: {
        'businessId': actor.businessId,
        'entity': mutation.entity,
        'entityId': mutation.entityId,
      },
    );
    final current = currentResult.isEmpty
        ? null
        : currentResult.single.toColumnMap();
    final currentVersion = current?['server_version'] as int? ?? 0;
    final expectedVersion = mutation.operation == 'criar'
        ? 0
        : mutation.localVersion;
    if (currentVersion != expectedVersion) {
      final serverPayload = _jsonMap(current?['payload']);
      await _saveOperation(
        tx,
        actor,
        mutation,
        'conflict',
        currentVersion,
        serverPayload,
      );
      return SyncResult(
        operationId: mutation.operationId,
        status: 'conflict',
        serverVersion: currentVersion,
        serverPayload: serverPayload,
      );
    }

    final nextVersion = currentVersion + 1;
    final deleted = mutation.operation == 'excluir';
    final payload = deleted ? <String, Object?>{} : mutation.payload;
    final parameters = {
      'businessId': actor.businessId,
      'entity': mutation.entity,
      'entityId': mutation.entityId,
      'version': nextVersion,
      'payload': jsonEncode(payload),
      'deleted': deleted,
      'userId': actor.userId,
    };
    await tx.execute(
      Sql.named('''
        INSERT INTO sync_records
          (business_id, entity, entity_id, server_version, payload,
           deleted, updated_by, updated_at)
        VALUES
          (@businessId, @entity, @entityId, @version,
           CAST(@payload AS jsonb), @deleted, @userId, now())
        ON CONFLICT (business_id, entity, entity_id)
        DO UPDATE SET server_version = EXCLUDED.server_version,
          payload = EXCLUDED.payload, deleted = EXCLUDED.deleted,
          updated_by = EXCLUDED.updated_by, updated_at = now()
      '''),
      parameters: parameters,
    );
    await tx.execute(
      Sql.named('''
        INSERT INTO sync_changes
          (business_id, entity, entity_id, server_version, payload,
           deleted, updated_by)
        VALUES
          (@businessId, @entity, @entityId, @version,
           CAST(@payload AS jsonb), @deleted, @userId)
      '''),
      parameters: parameters,
    );
    await _saveOperation(tx, actor, mutation, 'applied', nextVersion, payload);
    return SyncResult(
      operationId: mutation.operationId,
      status: 'applied',
      serverVersion: nextVersion,
      serverPayload: payload,
    );
  }

  static Future<void> _saveOperation(
    Session tx,
    AuthContext actor,
    SyncMutation mutation,
    String status,
    int serverVersion,
    Map<String, Object?>? serverPayload,
  ) async {
    await tx.execute(
      Sql.named('''
        INSERT INTO sync_operations
          (operation_id, business_id, user_id, entity, entity_id,
           status, server_version, server_payload)
        VALUES
          (@operationId, @businessId, @userId, @entity, @entityId,
           @status, @serverVersion, CAST(@serverPayload AS jsonb))
      '''),
      parameters: {
        'operationId': mutation.operationId,
        'businessId': actor.businessId,
        'userId': actor.userId,
        'entity': mutation.entity,
        'entityId': mutation.entityId,
        'status': status,
        'serverVersion': serverVersion,
        'serverPayload': jsonEncode(serverPayload),
      },
    );
  }

  @override
  Future<List<SyncChange>> pullChanges({
    required String businessId,
    required int afterCursor,
    required int limit,
  }) {
    return _pool.runTx((tx) async {
      await _setTenant(tx, businessId);
      final result = await tx.execute(
        Sql.named('''
          SELECT cursor, entity, entity_id, server_version, payload,
                 deleted, updated_at
          FROM sync_changes
          WHERE business_id = @businessId AND cursor > @afterCursor
          ORDER BY cursor LIMIT @limit
        '''),
        parameters: {
          'businessId': businessId,
          'afterCursor': afterCursor,
          'limit': limit.clamp(1, 500),
        },
      );
      return result.map((entry) {
        final row = entry.toColumnMap();
        return SyncChange(
          cursor: row['cursor'] as int,
          entity: row['entity'] as String,
          entityId: row['entity_id'] as String,
          serverVersion: row['server_version'] as int,
          deleted: row['deleted'] as bool,
          payload: _jsonMap(row['payload']) ?? const {},
          updatedAt: row['updated_at'] as DateTime,
        );
      }).toList();
    });
  }

  @override
  Future<void> createPasswordReset({
    required String id,
    required String userId,
    required String businessId,
    required String tokenHash,
    required String channel,
    required DateTime expiresAt,
  }) {
    return _pool.runTx((tx) async {
      await _setTenant(tx, businessId);
      await tx.execute(
        Sql.named('''
          INSERT INTO password_reset_tokens
            (id, user_id, business_id, token_hash, channel, expires_at)
          VALUES
            (@id, @userId, @businessId, @tokenHash, @channel, @expiresAt)
        '''),
        parameters: {
          'id': id,
          'userId': userId,
          'businessId': businessId,
          'tokenHash': tokenHash,
          'channel': channel,
          'expiresAt': expiresAt,
        },
      );
    });
  }

  @override
  Future<AccountIdentity?> consumePasswordReset({
    required String tokenHash,
    required String newPasswordHash,
  }) {
    return _pool.runTx((tx) async {
      await _allowAuthLookup(tx);
      final tokenResult = await tx.execute(
        Sql.named('''
          SELECT id, user_id, business_id
          FROM password_reset_tokens
          WHERE token_hash = @tokenHash
            AND consumed_at IS NULL AND expires_at > now()
          FOR UPDATE
        '''),
        parameters: {'tokenHash': tokenHash},
      );
      if (tokenResult.isEmpty) return null;
      final token = tokenResult.single.toColumnMap();
      final businessId = token['business_id'] as String;
      await _setTenant(tx, businessId);
      await tx.execute(
        Sql.named('''
          UPDATE users SET password_hash = @passwordHash, updated_at = now()
          WHERE id = @userId AND business_id = @businessId
        '''),
        parameters: {
          'passwordHash': newPasswordHash,
          'userId': token['user_id'],
          'businessId': businessId,
        },
      );
      await tx.execute(
        Sql.named('''
          UPDATE password_reset_tokens SET consumed_at = now() WHERE id = @id
        '''),
        parameters: {'id': token['id']},
      );
      await tx.execute(
        Sql.named('''
          UPDATE sessions SET revoked_at = now()
          WHERE user_id = @userId AND business_id = @businessId
            AND revoked_at IS NULL
        '''),
        parameters: {'userId': token['user_id'], 'businessId': businessId},
      );
      final user = await tx.execute(
        Sql.named('''
          SELECT u.id, u.business_id, b.display_name AS business_name,
                 u.name, u.phone, u.login, u.password_hash, u.role, u.active
          FROM users u INNER JOIN businesses b ON b.id = u.business_id
          WHERE u.id = @userId AND u.business_id = @businessId
        '''),
        parameters: {'userId': token['user_id'], 'businessId': businessId},
      );
      return _accountFromRow(user.single.toColumnMap());
    });
  }

  static Future<void> _setTenant(Session executor, String businessId) async {
    await executor.execute(
      Sql.named("SELECT set_config('app.business_id', @id, true)"),
      parameters: {'id': businessId},
    );
  }

  static Future<void> _allowAuthLookup(Session executor) async {
    await executor.execute("SELECT set_config('app.auth_lookup', '1', true)");
  }

  static AccountIdentity _accountFromRow(
    Map<String, dynamic> row, [
    String? businessName,
  ]) {
    return AccountIdentity(
      userId: row['id'] as String,
      businessId: row['business_id'] as String,
      businessName: businessName ?? row['business_name'] as String,
      userName: row['name'] as String,
      phone: row['phone'] as String,
      login: row['login'] as String,
      role: row['role'] as String,
      passwordHash: row['password_hash'] as String,
      active: row['active'] as bool,
    );
  }

  static Map<String, Object?>? _jsonMap(Object? value) {
    if (value == null) return null;
    if (value is Map) return Map<String, Object?>.from(value);
    if (value is String) {
      return Map<String, Object?>.from(jsonDecode(value) as Map);
    }
    throw StateError('JSON inesperado retornado pelo PostgreSQL.');
  }

  @override
  Future<void> close() => _pool.close();
}
