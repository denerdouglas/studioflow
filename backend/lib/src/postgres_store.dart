import 'dart:convert';

import 'package:postgres/postgres.dart';

import 'package:studioflow_backend/src/database_config.dart';

import 'models.dart';
import 'store.dart';
import 'package:studioflow_backend/src/admin.dart';
import 'package:studioflow_backend/src/public_booking.dart';

final class PostgresBackendStore
    implements BackendStore, AdminBackendStore, PublicBookingStore {
  final Pool _pool;

  Pool get pool => _pool;

  PostgresBackendStore._(this._pool);

  factory PostgresBackendStore.fromUrl(String databaseUrl) {
    return PostgresBackendStore._(DatabaseConfig.createPool(databaseUrl));
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
    bool moduloLojaAtivo = true,
    bool moduloServicosAtivo = true,
    String? moduleConfiguration,
  }) {
    return _pool.runTx((tx) async {
      await _setTenant(tx, businessId);
      await tx.execute(
        Sql.named('''
          INSERT INTO businesses
            (id, name, display_name, segment, modulo_loja_ativo,
             modulo_servicos_ativo, module_configuration)
          VALUES
            (@id, @name, @name, @segment, @loja, @servicos,
             CAST(@modules AS jsonb))
        '''),
        parameters: {
          'id': businessId,
          'name': businessName,
          'segment': segment,
          'loja': moduloLojaAtivo,
          'servicos': moduloServicosAtivo,
          'modules': moduleConfiguration,
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
      return _accountFromRow({
        ...result.single.toColumnMap(),
        'segment': segment,
        'modulo_loja_ativo': moduloLojaAtivo,
        'modulo_servicos_ativo': moduloServicosAtivo,
        'module_configuration': moduleConfiguration,
      }, businessName);
    });
  }

  @override
  Future<List<AccountIdentity>> findAccountsByLogin(String normalizedLogin) {
    return _pool.runTx((tx) async {
      await _allowAuthLookup(tx);
      final result = await tx.execute(
        Sql.named('''
          SELECT u.id, u.business_id, b.display_name AS business_name,
                 u.name, u.phone, u.login, u.password_hash, u.role, u.active,
                 b.booking_slug, b.booking_enabled, b.modulo_loja_ativo,
                 b.modulo_servicos_ativo, b.segment,
                 b.module_configuration::text AS module_configuration
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
  @override
  Future<void> updateBusinessModules({
    required String businessId,
    required bool moduloLojaAtivo,
    required bool moduloServicosAtivo,
    String? moduleConfiguration,
  }) {
    return _pool.runTx((tx) async {
      await _setTenant(tx, businessId);
      await tx.execute(
        Sql.named('''UPDATE businesses
             SET modulo_loja_ativo = @loja,
                 modulo_servicos_ativo = @servicos,
                 module_configuration = COALESCE(
                   CAST(@modules AS jsonb), module_configuration),
                 updated_at = now()
             WHERE id = @id'''),
        parameters: {
          'id': businessId,
          'loja': moduloLojaAtivo,
          'servicos': moduloServicosAtivo,
          'modules': moduleConfiguration,
        },
      );
    });
  }

  @override
  Future<AccountIdentity?> findAccount(String userId, String businessId) {
    return _pool.runTx((tx) async {
      await _setTenant(tx, businessId);
      final result = await tx.execute(
        Sql.named('''
          SELECT u.id, u.business_id, b.display_name AS business_name,
                 u.name, u.phone, u.login, u.password_hash, u.role, u.active,
                 b.booking_slug, b.booking_enabled, b.modulo_loja_ativo,
                 b.modulo_servicos_ativo, b.segment,
                 b.module_configuration::text AS module_configuration
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
      await _setTenant(tx, actor.businessId!);
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
        'businessId': actor.businessId!,
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
        'businessId': actor.businessId!,
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
      'businessId': actor.businessId!,
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
        'businessId': actor.businessId!,
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
                 u.name, u.phone, u.login, u.password_hash, u.role, u.active,
                 b.booking_slug, b.booking_enabled, b.modulo_loja_ativo,
                 b.modulo_servicos_ativo, b.segment,
                 b.module_configuration::text AS module_configuration
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
      bookingSlug: row['booking_slug'] as String?,
      bookingEnabled: row['booking_enabled'] as bool?,
      moduloLojaAtivo: row['modulo_loja_ativo'] as bool? ?? true,
      moduloServicosAtivo: row['modulo_servicos_ativo'] as bool? ?? true,
      segment: row['segment'] as String?,
      moduleConfiguration: row['module_configuration'] as String?,
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
  Future<PlatformAdmin?> findPlatformAdminByUserId(String userId) async {
    final result = await _pool.execute(
      Sql.named('''
        SELECT id, user_id, role, active, permissions, created_at
        FROM platform_admins
        WHERE user_id = @userId AND active = true
      '''),
      parameters: {'userId': userId},
    );
    if (result.isEmpty) return null;
    final row = result.single.toColumnMap();
    return PlatformAdmin(
      id: row['id'] as String,
      userId: row['user_id'] as String,
      role: row['role'] as String,
      active: row['active'] as bool,
      permissions: row['permissions'] as Map<String, dynamic>? ?? {},
      createdAt: row['created_at'] as DateTime,
    );
  }

  @override
  Future<PublicBookingBusiness> ensurePublicBooking({
    required String businessId,
    required String businessName,
  }) {
    return _pool.runTx((tx) async {
      await tx.execute(
        Sql.named("SELECT pg_advisory_xact_lock(hashtext(@id))"),
        parameters: {'id': businessId},
      );
      final current = await tx.execute(
        Sql.named(
          'SELECT booking_slug, booking_enabled, display_name, logo_url, cover_url, color_primary, color_secondary, phone, whatsapp, instagram, city, state FROM businesses WHERE id = @id',
        ),
        parameters: {'id': businessId},
      );
      if (current.isEmpty) throw StateError('Estabelecimento não encontrado.');
      final row = current.single.toColumnMap();
      var slug = row['booking_slug'] as String?;
      if (slug == null || slug.isEmpty) {
        var base = PublicBookingSlug.normalize(businessName);
        if (base.length < 3 || PublicBookingSlug.reserved.contains(base)) {
          base =
              'studio-${businessId.substring(0, businessId.length < 8 ? businessId.length : 8)}';
        }
        slug = base;
        var suffix = 2;
        while ((await tx.execute(
          Sql.named('SELECT 1 FROM businesses WHERE booking_slug = @slug'),
          parameters: {'slug': slug},
        )).isNotEmpty) {
          slug = '$base-${suffix++}';
        }
        await tx.execute(
          Sql.named(
            "UPDATE businesses SET booking_slug=@slug, booking_enabled=TRUE, booking_public_url=@url, booking_created_at=COALESCE(booking_created_at, now()), booking_updated_at=now() WHERE id=@id",
          ),
          parameters: {
            'id': businessId,
            'slug': slug,
            'url': 'https://studioflowapp.com.br/agendar/$slug',
          },
        );
      }
      return _publicBusiness(businessId, slug!, row);
    });
  }

  @override
  Future<PublicBookingBusiness?> findPublicBooking(String slug) async {
    final result = await _pool.execute(
      Sql.named(
        'SELECT id, booking_slug, booking_enabled, display_name, logo_url, cover_url, color_primary, color_secondary, phone, whatsapp, instagram, city, state FROM businesses WHERE booking_slug=@slug OR old_booking_slugs @> to_jsonb(ARRAY[@slug]::text[]) LIMIT 1',
      ),
      parameters: {'slug': slug},
    );
    if (result.isEmpty) return null;
    final row = result.single.toColumnMap();
    return _publicBusiness(
      row['id'] as String,
      row['booking_slug'] as String,
      row,
    );
  }

  PublicBookingBusiness _publicBusiness(
    String id,
    String slug,
    Map<String, Object?> row,
  ) => PublicBookingBusiness(
    businessId: id,
    slug: slug,
    name: row['display_name'] as String? ?? 'StudioFlow',
    enabled: row['booking_enabled'] as bool? ?? true,
    profile: {
      for (final key in const [
        'logo_url',
        'cover_url',
        'color_primary',
        'color_secondary',
        'phone',
        'whatsapp',
        'instagram',
        'city',
        'state',
      ])
        if (row[key] != null) key: row[key],
    },
  );

  @override
  Future<List<Map<String, Object?>>> publicEntities({
    required String businessId,
    required String entity,
  }) async {
    final result = await _pool.execute(
      Sql.named(
        "SELECT entity_id, payload FROM sync_records WHERE business_id=@businessId AND entity=@entity AND deleted=FALSE AND COALESCE(payload->>'ativo','true') NOT IN ('false','0') ORDER BY payload->>'nome'",
      ),
      parameters: {'businessId': businessId, 'entity': entity},
    );
    const allowed = {
      'id',
      'nome',
      'preco',
      'duracao_minutos',
      'unidade_id',
      'profissional_id',
      'servico_id',
      'horario_abertura',
      'horario_fechamento',
    };
    return result.map((row) {
      final payload = row.toColumnMap()['payload'];
      final data = Map<String, Object?>.from(
        payload is Map ? payload : jsonDecode(payload.toString()) as Map,
      );
      data['id'] ??= row.toColumnMap()['entity_id'];
      data.removeWhere((key, _) => !allowed.contains(key));
      return data;
    }).toList();
  }

  @override
  Future<List<Map<String, Object?>>> publicSchedulingRecords({
    required String businessId,
    required Set<String> entities,
  }) async {
    final records = <Map<String, Object?>>[];
    for (final entity in entities) {
      final rows = await _pool.execute(
        Sql.named(
          'SELECT entity_id, payload FROM sync_records WHERE business_id=@businessId AND entity=@entity AND deleted=FALSE',
        ),
        parameters: {'businessId': businessId, 'entity': entity},
      );
      for (final row in rows) {
        final columns = row.toColumnMap();
        final raw = columns['payload'];
        final payload = Map<String, Object?>.from(
          raw is Map ? raw : jsonDecode(raw.toString()) as Map,
        );
        records.add({
          ...payload,
          '_entity': entity,
          'id': payload['id'] ?? columns['entity_id'],
        });
      }
    }
    return records;
  }

  @override
  Future<PublicAppointment> createPublicAppointment({
    required String businessId,
    required String idempotencyKey,
    required String tokenHash,
    required String publicToken,
    required String serviceId,
    String? professionalId,
    String? unitId,
    required String clientName,
    required String clientPhone,
    String? notes,
    required DateTime startsAt,
    required DateTime endsAt,
  }) => _pool.runTx((tx) async {
    final lockKey =
        '$businessId::${professionalId ?? 'any'}::${startsAt.toUtc().toIso8601String()}';
    await tx.execute(
      Sql.named('SELECT pg_advisory_xact_lock(hashtext(@key))'),
      parameters: {'key': lockKey},
    );
    final previous = await tx.execute(
      Sql.named(
        'SELECT * FROM public_appointments WHERE business_id=@businessId AND idempotency_key=@key',
      ),
      parameters: {'businessId': businessId, 'key': idempotencyKey},
    );
    if (previous.isNotEmpty) {
      return _appointment(previous.single.toColumnMap(), '');
    }
    final owner = await tx.execute(
      Sql.named(
        "SELECT id FROM users WHERE business_id=@businessId AND active=TRUE ORDER BY CASE role WHEN 'dono' THEN 0 ELSE 1 END LIMIT 1",
      ),
      parameters: {'businessId': businessId},
    );
    if (owner.isEmpty) {
      throw StateError('Estabelecimento sem responsável ativo.');
    }
    final userId = owner.single.toColumnMap()['id'] as String;
    final valid = await tx.execute(
      Sql.named('''
      SELECT
        EXISTS(SELECT 1 FROM sync_records WHERE business_id=@businessId
          AND entity='servicos' AND entity_id=@serviceId AND deleted=FALSE
          AND COALESCE(payload->>'ativo','true') NOT IN ('false','0')) service_ok,
        EXISTS(SELECT 1 FROM sync_records WHERE business_id=@businessId
          AND entity='profissionais' AND entity_id=@professionalId
          AND deleted=FALSE
          AND COALESCE(payload->>'ativo','true') NOT IN ('false','0')) professional_ok,
        (CAST(@unitId AS TEXT) IS NULL OR EXISTS(SELECT 1 FROM sync_records
          WHERE business_id=@businessId AND entity='unidades'
            AND entity_id=CAST(@unitId AS TEXT) AND deleted=FALSE)) unit_ok,
        NOT EXISTS(SELECT 1 FROM sync_records links
          WHERE links.business_id=@businessId
            AND links.entity='profissional_servicos' AND links.deleted=FALSE
            AND links.payload->>'profissional_id'=@professionalId)
        OR EXISTS(SELECT 1 FROM sync_records links
          WHERE links.business_id=@businessId
            AND links.entity='profissional_servicos' AND links.deleted=FALSE
            AND links.payload->>'profissional_id'=@professionalId
            AND links.payload->>'servico_id'=@serviceId) link_ok
    '''),
      parameters: {
        'businessId': businessId,
        'serviceId': serviceId,
        'professionalId': professionalId,
        'unitId': unitId,
      },
    );
    final checks = valid.single.toColumnMap();
    if (checks['service_ok'] != true ||
        checks['professional_ok'] != true ||
        checks['unit_ok'] != true ||
        checks['link_ok'] != true) {
      throw StateError('Serviço, profissional ou unidade indisponível.');
    }
    final serviceRows = await tx.execute(
      Sql.named('''
        SELECT payload
        FROM sync_records
        WHERE business_id=@businessId
          AND entity='servicos'
          AND entity_id=@serviceId
          AND deleted=FALSE
        LIMIT 1
      '''),
      parameters: {'businessId': businessId, 'serviceId': serviceId},
    );

    final rawServicePayload = serviceRows.single.toColumnMap()['payload'];
    final servicePayload = Map<String, Object?>.from(
      rawServicePayload is Map
          ? rawServicePayload
          : jsonDecode(rawServicePayload.toString()) as Map,
    );

    final rawPreco = servicePayload['preco'];
    final valorServico = rawPreco is num
        ? rawPreco.toDouble()
        : double.tryParse(rawPreco?.toString().replaceAll(',', '.') ?? '') ??
              0.0;

    final agora = DateTime.now().toUtc().toIso8601String();

    final conflict = await tx.execute(
      Sql.named('''
      SELECT 1 FROM (
        SELECT starts_at inicio, ends_at fim FROM public_appointments
        WHERE business_id=@businessId AND status NOT IN ('cancelado','rejeitado')
          AND professional_id IS NOT DISTINCT FROM @professionalId
        UNION ALL
        SELECT (payload->>'inicio')::timestamptz, (payload->>'fim')::timestamptz
        FROM sync_records WHERE business_id=@businessId
          AND entity='agendamentos' AND deleted=FALSE
          AND payload->>'profissional_id' IS NOT DISTINCT FROM @professionalId
          AND COALESCE(payload->>'status','agendado') <> 'cancelado'
      ) x WHERE inicio < @endsAt AND fim > @startsAt LIMIT 1
    '''),
      parameters: {
        'businessId': businessId,
        'professionalId': professionalId,
        'startsAt': startsAt.toUtc(),
        'endsAt': endsAt.toUtc(),
      },
    );
    if (conflict.isNotEmpty) throw StateError('Horário indisponível.');
    final phone = clientPhone.replaceAll(RegExp(r'D'), '');
    final clients = await tx.execute(
      Sql.named('''
      SELECT entity_id FROM sync_records
      WHERE business_id=@businessId AND entity='clientes' AND deleted=FALSE
        AND regexp_replace(COALESCE(payload->>'whatsapp',
          payload->>'telefone',''),'D','','g')=@phone LIMIT 1
    '''),
      parameters: {'businessId': businessId, 'phone': phone},
    );
    final clientId = clients.isEmpty
        ? 'public_client_${tokenHash.substring(0, 20)}'
        : clients.single.toColumnMap()['entity_id'] as String;
    if (clients.isEmpty) {
      await _upsertPublicSync(tx, businessId, userId, 'clientes', clientId, {
        'id': clientId,
        'comercio_id': businessId,
        'nome': clientName,
        'whatsapp': phone,
        'telefone': phone,
        'ativo': true,
        'data_cadastro': DateTime.now().toUtc().toIso8601String(),
      });
    }
    final appointmentId = 'public_appointment_${tokenHash.substring(0, 20)}';
    await _upsertPublicSync(
      tx,
      businessId,
      userId,
      'agendamentos',
      appointmentId,
      {
        'id': appointmentId,
        'business_id': businessId,
        'comercio_id': businessId,
        'unidade_id': unitId,
        'cliente_id': clientId,
        'profissional_id': professionalId,
        'servico_id': serviceId,
        'inicio': startsAt.toUtc().toIso8601String(),
        'fim': endsAt.toUtc().toIso8601String(),
        'origem': 'agendamento_publico',
        'status': 'agendado',
        'forma_pagamento': null,
        'valor_servico': valorServico,
        'desconto': 0.0,
        'valor_recebido': 0.0,
        'confirmado': 0,
        'compareceu': 0,
        'observacoes': notes ?? '',
        'data_criacao': agora,
        'created_at': agora,
        'updated_at': agora,
        'encaixe': 0,
        'estoque_consumido': 0,
        'excluido': 0,
      },
    );
    final result = await tx.execute(
      Sql.named('''
      INSERT INTO public_appointments
        (id,public_token_hash,idempotency_key,business_id,unit_id,service_id,
         professional_id,client_id,appointment_id,client_name,client_phone,
         notes,starts_at,ends_at)
      VALUES(@id,@hash,@key,@businessId,@unitId,@serviceId,@professionalId,
        @clientId,@appointmentId,@name,@phone,@notes,@startsAt,@endsAt)
      RETURNING *
    '''),
      parameters: {
        'id': 'pub_${tokenHash.substring(0, 24)}',
        'hash': tokenHash,
        'key': idempotencyKey,
        'businessId': businessId,
        'unitId': unitId,
        'serviceId': serviceId,
        'professionalId': professionalId,
        'clientId': clientId,
        'appointmentId': appointmentId,
        'name': clientName,
        'phone': phone,
        'notes': notes,
        'startsAt': startsAt.toUtc(),
        'endsAt': endsAt.toUtc(),
      },
    );
    await tx.execute(
      Sql.named('''
      INSERT INTO audit_logs(event,business_id,user_id,success,details)
      VALUES('public_booking.created',@businessId,@userId,TRUE,
        CAST(@details AS jsonb))
    '''),
      parameters: {
        'businessId': businessId,
        'userId': userId,
        'details': jsonEncode({'appointmentId': appointmentId}),
      },
    );
    return _appointment(result.single.toColumnMap(), publicToken);
  });
  @override
  Future<PublicAppointment?> findPublicAppointmentByIdempotency({
    required String businessId,
    required String idempotencyKey,
  }) async {
    final result = await _pool.execute(
      Sql.named(
        'SELECT * FROM public_appointments WHERE business_id=@businessId AND idempotency_key=@key',
      ),
      parameters: {'businessId': businessId, 'key': idempotencyKey},
    );
    return result.isEmpty
        ? null
        : _appointment(result.single.toColumnMap(), '');
  }

  @override
  Future<PublicAppointment?> findPublicAppointment(String tokenHash) async {
    final result = await _pool.execute(
      Sql.named(
        'SELECT * FROM public_appointments WHERE public_token_hash=@hash',
      ),
      parameters: {'hash': tokenHash},
    );
    return result.isEmpty
        ? null
        : _appointment(result.single.toColumnMap(), '');
  }

  @override
  Future<PublicAppointment?> updatePublicAppointment({
    required String tokenHash,
    required String status,
    DateTime? startsAt,
    DateTime? endsAt,
  }) => _pool.runTx((tx) async {
    final found = await tx.execute(
      Sql.named(
        'SELECT * FROM public_appointments WHERE public_token_hash=@hash FOR UPDATE',
      ),
      parameters: {'hash': tokenHash},
    );
    if (found.isEmpty) return null;
    final row = found.single.toColumnMap();
    final businessId = row['business_id'] as String;
    final appointmentId = row['appointment_id'] as String?;
    if (appointmentId == null) throw StateError('Vínculo principal ausente.');
    final owner = await tx.execute(
      Sql.named(
        "SELECT id FROM users WHERE business_id=@businessId AND active=TRUE ORDER BY CASE role WHEN 'dono' THEN 0 ELSE 1 END LIMIT 1",
      ),
      parameters: {'businessId': businessId},
    );
    if (owner.isEmpty) {
      throw StateError('Estabelecimento sem responsável ativo.');
    }
    final userId = owner.single.toColumnMap()['id'] as String;
    final main = await tx.execute(
      Sql.named(
        "SELECT payload FROM sync_records WHERE business_id=@businessId AND entity='agendamentos' AND entity_id=@appointmentId AND deleted=FALSE FOR UPDATE",
      ),
      parameters: {'businessId': businessId, 'appointmentId': appointmentId},
    );
    if (main.isEmpty) throw StateError('Agendamento principal ausente.');
    final raw = main.single.toColumnMap()['payload'];
    final payload = Map<String, Object?>.from(
      raw is Map ? raw : jsonDecode(raw.toString()) as Map,
    );
    var nextStart = startsAt ?? row['starts_at'] as DateTime;
    var nextEnd = endsAt ?? row['ends_at'] as DateTime;
    if (startsAt != null) {
      final service = await tx.execute(
        Sql.named(
          "SELECT payload FROM sync_records WHERE business_id=@businessId AND entity='servicos' AND entity_id=@serviceId AND deleted=FALSE",
        ),
        parameters: {'businessId': businessId, 'serviceId': row['service_id']},
      );
      if (service.isEmpty) throw StateError('Serviço indisponível.');
      final serviceRaw = service.single.toColumnMap()['payload'];
      final servicePayload = serviceRaw is Map
          ? serviceRaw
          : jsonDecode(serviceRaw.toString()) as Map;
      final minutes =
          ((servicePayload['duracao_minutos'] as num?)?.toInt() ?? 0).clamp(
            1,
            480,
          );
      nextStart = startsAt.toUtc();
      nextEnd = nextStart.add(Duration(minutes: minutes));
      final conflict = await tx.execute(
        Sql.named('''
        SELECT 1 FROM sync_records WHERE business_id=@businessId
          AND entity='agendamentos' AND entity_id<>@appointmentId
          AND deleted=FALSE
          AND payload->>'profissional_id' IS NOT DISTINCT FROM @professionalId
          AND COALESCE(payload->>'status','agendado') <> 'cancelado'
          AND (payload->>'inicio')::timestamptz < @endsAt
          AND (payload->>'fim')::timestamptz > @startsAt LIMIT 1
      '''),
        parameters: {
          'businessId': businessId,
          'appointmentId': appointmentId,
          'professionalId': row['professional_id'],
          'startsAt': nextStart,
          'endsAt': nextEnd,
        },
      );
      if (conflict.isNotEmpty) throw StateError('Horário indisponível.');
    }
    payload['status'] = status;
    payload['inicio'] = nextStart.toUtc().toIso8601String();
    payload['fim'] = nextEnd.toUtc().toIso8601String();
    await _upsertPublicSync(
      tx,
      businessId,
      userId,
      'agendamentos',
      appointmentId,
      payload,
    );
    final updated = await tx.execute(
      Sql.named('''
      UPDATE public_appointments SET status=@status,starts_at=@startsAt,
        ends_at=@endsAt,updated_at=now()
      WHERE public_token_hash=@hash RETURNING *
    '''),
      parameters: {
        'hash': tokenHash,
        'status': status,
        'startsAt': nextStart.toUtc(),
        'endsAt': nextEnd.toUtc(),
      },
    );
    await tx.execute(
      Sql.named('''
      INSERT INTO audit_logs(event,business_id,user_id,success,details)
      VALUES(@event,@businessId,@userId,TRUE,CAST(@details AS jsonb))
    '''),
      parameters: {
        'event': 'public_booking.$status',
        'businessId': businessId,
        'userId': userId,
        'details': jsonEncode({'appointmentId': appointmentId}),
      },
    );
    return _appointment(updated.single.toColumnMap(), '');
  });
  Future<void> _upsertPublicSync(
    Session tx,
    String businessId,
    String userId,
    String entity,
    String entityId,
    Map<String, Object?> payload,
  ) async {
    final current = await tx.execute(
      Sql.named(
        'SELECT server_version FROM sync_records WHERE business_id=@businessId AND entity=@entity AND entity_id=@entityId FOR UPDATE',
      ),
      parameters: {
        'businessId': businessId,
        'entity': entity,
        'entityId': entityId,
      },
    );
    final version = current.isEmpty
        ? 1
        : (current.single.toColumnMap()['server_version'] as int) + 1;
    final parameters = {
      'businessId': businessId,
      'entity': entity,
      'entityId': entityId,
      'version': version,
      'payload': jsonEncode(payload),
      'userId': userId,
    };
    await tx.execute(
      Sql.named('''
      INSERT INTO sync_records(business_id,entity,entity_id,server_version,
        payload,deleted,updated_by,updated_at)
      VALUES(@businessId,@entity,@entityId,@version,CAST(@payload AS jsonb),
        FALSE,@userId,now())
      ON CONFLICT(business_id,entity,entity_id) DO UPDATE SET
        server_version=EXCLUDED.server_version,payload=EXCLUDED.payload,
        deleted=FALSE,updated_by=EXCLUDED.updated_by,updated_at=now()
    '''),
      parameters: parameters,
    );
    await tx.execute(
      Sql.named('''
      INSERT INTO sync_changes(business_id,entity,entity_id,server_version,
        payload,deleted,updated_by)
      VALUES(@businessId,@entity,@entityId,@version,CAST(@payload AS jsonb),
        FALSE,@userId)
    '''),
      parameters: parameters,
    );
  }

  PublicAppointment _appointment(Map<String, Object?> row, String token) =>
      PublicAppointment(
        token: token,
        businessId: row['business_id'] as String,
        serviceId: row['service_id'] as String,
        professionalId: row['professional_id'] as String?,
        startsAt: row['starts_at'] as DateTime,
        endsAt: row['ends_at'] as DateTime,
        status: row['status'] as String,
      );

  @override
  Future<void> close() => _pool.close();
}
