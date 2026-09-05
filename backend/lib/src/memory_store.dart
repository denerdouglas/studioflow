import 'models.dart';
import 'marketplace.dart';
import 'store.dart';
import 'admin.dart';
import 'public_booking.dart';

final class MemoryBackendStore
    implements
        BackendStore,
        MarketplaceBackendStore,
        AdminBackendStore,
        PublicBookingStore {
  final Map<String, AccountIdentity> _accounts = {};
  final Map<String, SessionRecord> _sessions = {};
  final Map<String, _ResetRecord> _resets = {};
  final Map<String, _SyncRecord> _records = {};
  final Map<String, SyncResult> _operations = {};
  final List<_BusinessChange> _changes = [];
  final List<Map<String, Object?>> audits = [];
  int _cursor = 0;
  final Map<String, PublicBookingBusiness> _publicBookings = {};
  final Map<String, PublicAppointment> _publicAppointments = {};
  final Map<String, String> _publicIdempotency = {};
  final Map<String, String> _publicMainAppointments = {};
  final Map<String, MarketplacePartner> _marketplacePartners = {};
  final Map<String, MarketplaceOffer> _marketplaceOffers = {};
  final List<Map<String, Object?>> _marketplaceDemands = [];
  final Map<String, MarketplacePartnerDomain> _marketplaceDomains = {};
  final Map<String, MarketplaceClick> _marketplaceClicks = {};
  final Map<String, PlatformAdmin> _platformAdmins = {};

  void seedPlatformAdmin(PlatformAdmin admin) {
    _platformAdmins[admin.userId] = admin;
  }

  void revokePlatformAdmin(String userId) {
    _platformAdmins.remove(userId);
  }

  String _accountKey(String userId, String businessId) =>
      '$businessId::$userId';
  String _recordKey(String businessId, String entity, String entityId) =>
      '$businessId::$entity::$entityId';

  @override
  Future<void> ping() async {}

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
  }) async {
    final account = AccountIdentity(
      userId: userId,
      businessId: businessId,
      businessName: businessName,
      userName: ownerName,
      phone: phone,
      login: login,
      role: 'dono',
      passwordHash: passwordHash,
      active: true,
      segment: segment,
      moduloLojaAtivo: moduloLojaAtivo,
      moduloServicosAtivo: moduloServicosAtivo,
      moduleConfiguration: moduleConfiguration,
    );
    _accounts[_accountKey(userId, businessId)] = account;
    return account;
  }

  @override
  Future<List<AccountIdentity>> findAccountsByLogin(
    String normalizedLogin,
  ) async {
    return _accounts.values
        .where(
          (account) =>
              account.active &&
              account.login.toLowerCase() == normalizedLogin.toLowerCase(),
        )
        .toList()
      ..sort((a, b) => a.businessName.compareTo(b.businessName));
  }

  @override
  @override
  Future<void> updateBusinessModules({
    required String businessId,
    required bool moduloLojaAtivo,
    required bool moduloServicosAtivo,
    String? moduleConfiguration,
  }) async {
    for (final entry in _accounts.entries.toList()) {
      final current = entry.value;
      if (current.businessId != businessId) continue;
      _accounts[entry.key] = AccountIdentity(
        userId: current.userId,
        businessId: current.businessId,
        businessName: current.businessName,
        userName: current.userName,
        phone: current.phone,
        login: current.login,
        role: current.role,
        passwordHash: current.passwordHash,
        active: current.active,
        segment: current.segment,
        moduloLojaAtivo: moduloLojaAtivo,
        moduloServicosAtivo: moduloServicosAtivo,
        moduleConfiguration: moduleConfiguration ?? current.moduleConfiguration,
      );
    }
  }

  @override
  Future<AccountIdentity?> findAccount(String userId, String businessId) async {
    return _accounts[_accountKey(userId, businessId)];
  }

  @override
  Future<void> createSession(SessionRecord session) async {
    _sessions[session.id] = session;
  }

  @override
  Future<SessionRecord?> findSessionByRefreshHash(String refreshHash) async {
    for (final session in _sessions.values) {
      if (session.refreshTokenHash == refreshHash) return session;
    }
    return null;
  }

  @override
  Future<void> rotateSession({
    required String sessionId,
    required String refreshHash,
    required DateTime expiresAt,
  }) async {
    final current = _sessions[sessionId];
    if (current == null || current.revoked) return;
    _sessions[sessionId] = SessionRecord(
      id: current.id,
      userId: current.userId,
      businessId: current.businessId,
      refreshTokenHash: refreshHash,
      expiresAt: expiresAt,
      revoked: false,
    );
  }

  @override
  Future<void> revokeSession(String sessionId) async {
    final current = _sessions[sessionId];
    if (current == null) return;
    _sessions[sessionId] = SessionRecord(
      id: current.id,
      userId: current.userId,
      businessId: current.businessId,
      refreshTokenHash: current.refreshTokenHash,
      expiresAt: current.expiresAt,
      revoked: true,
    );
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
    audits.add({
      'event': event,
      'businessId': businessId,
      'userId': userId,
      'sessionId': sessionId,
      'success': success,
      'details': details,
    });
  }

  @override
  Future<List<SyncResult>> applyMutations({
    required AuthContext actor,
    required List<SyncMutation> mutations,
  }) async {
    final results = <SyncResult>[];
    for (final mutation in mutations) {
      final previous = _operations[mutation.operationId];
      if (previous != null) {
        results.add(previous);
        continue;
      }
      final key = _recordKey(
        actor.businessId!,
        mutation.entity,
        mutation.entityId,
      );
      final current = _records[key];
      final expected = mutation.operation == 'criar'
          ? 0
          : mutation.localVersion;
      final currentVersion = current?.version ?? 0;
      if (expected != currentVersion) {
        final conflict = SyncResult(
          operationId: mutation.operationId,
          status: 'conflict',
          serverVersion: currentVersion,
          serverPayload: current?.payload,
        );
        _operations[mutation.operationId] = conflict;
        results.add(conflict);
        continue;
      }
      final version = currentVersion + 1;
      final deleted = mutation.operation == 'excluir';
      final payload = deleted ? <String, Object?>{} : mutation.payload;
      _records[key] = _SyncRecord(version, payload);
      final change = SyncChange(
        cursor: ++_cursor,
        entity: mutation.entity,
        entityId: mutation.entityId,
        serverVersion: version,
        deleted: deleted,
        payload: payload,
        updatedAt: DateTime.now().toUtc(),
      );
      _changes.add(_BusinessChange(actor.businessId!, change));
      final applied = SyncResult(
        operationId: mutation.operationId,
        status: 'applied',
        serverVersion: version,
        serverPayload: payload,
      );
      _operations[mutation.operationId] = applied;
      results.add(applied);
    }
    return results;
  }

  @override
  Future<List<SyncChange>> pullChanges({
    required String businessId,
    required int afterCursor,
    required int limit,
  }) async {
    return _changes
        .where(
          (entry) =>
              entry.businessId == businessId &&
              entry.change.cursor > afterCursor,
        )
        .take(limit.clamp(1, 500))
        .map((entry) => entry.change)
        .toList();
  }

  @override
  Future<void> createPasswordReset({
    required String id,
    required String userId,
    required String businessId,
    required String tokenHash,
    required String channel,
    required DateTime expiresAt,
  }) async {
    _resets[tokenHash] = _ResetRecord(
      userId: userId,
      businessId: businessId,
      expiresAt: expiresAt,
    );
  }

  @override
  Future<AccountIdentity?> consumePasswordReset({
    required String tokenHash,
    required String newPasswordHash,
  }) async {
    final reset = _resets.remove(tokenHash);
    if (reset == null || !reset.expiresAt.isAfter(DateTime.now().toUtc())) {
      return null;
    }
    final key = _accountKey(reset.userId, reset.businessId);
    final current = _accounts[key];
    if (current == null) return null;
    final updated = AccountIdentity(
      userId: current.userId,
      businessId: current.businessId,
      businessName: current.businessName,
      userName: current.userName,
      phone: current.phone,
      login: current.login,
      role: current.role,
      passwordHash: newPasswordHash,
      active: current.active,
      segment: current.segment,
      moduloLojaAtivo: current.moduloLojaAtivo,
      moduloServicosAtivo: current.moduloServicosAtivo,
      moduleConfiguration: current.moduleConfiguration,
    );
    _accounts[key] = updated;
    for (final session
        in _sessions.values
            .where(
              (session) =>
                  session.userId == reset.userId &&
                  session.businessId == reset.businessId,
            )
            .toList()) {
      await revokeSession(session.id);
    }
    return updated;
  }

  @override
  Future<PlatformAdmin?> findPlatformAdminByUserId(String userId) async =>
      _platformAdmins[userId];

  @override
  Future<List<MarketplacePartner>> listActivePartners() async =>
      _marketplacePartners.values
          .where((partner) => partner.status == 'active')
          .toList();
  @override
  Future<List<MarketplacePartner>> listAllPartners() async =>
      _marketplacePartners.values.toList();
  @override
  Future<MarketplacePartner?> findPartnerById(String id) async =>
      _marketplacePartners[id];
  @override
  Future<void> savePartner(MarketplacePartner partner) async =>
      _marketplacePartners[partner.id] = partner;
  @override
  Future<List<MarketplaceOffer>> searchOffers(String query) async {
    final normalized = query.trim().toLowerCase();
    return _marketplaceOffers.values.where((offer) {
      if (!offer.active ||
          !_marketplacePartners.containsKey(offer.partnerId) ||
          _marketplacePartners[offer.partnerId]!.status != 'active') {
        return false;
      }
      final terms = [
        offer.title,
        offer.seller,
        offer.brand,
        offer.category,
        offer.gtin,
        offer.productCode,
        ...offer.keywords,
      ].whereType<String>().join(' ').toLowerCase();
      return normalized.split(RegExp(r'\s+')).every(terms.contains);
    }).toList();
  }

  @override
  Future<List<MarketplaceOffer>> listOffers() async =>
      _marketplaceOffers.values.toList();
  @override
  Future<void> saveOffer(MarketplaceOffer offer) async =>
      _marketplaceOffers[offer.id] = offer;
  @override
  Future<List<MarketplaceClick>> listClicks() async =>
      _marketplaceClicks.values.toList();
  @override
  Future<List<Map<String, Object?>>> listSearchDemands() async =>
      List.unmodifiable(_marketplaceDemands);
  @override
  Future<List<MarketplacePartnerDomain>> listDomainsForPartner(
    String partnerId,
  ) async => _marketplaceDomains.values
      .where((domain) => domain.partnerId == partnerId)
      .toList();
  @override
  Future<void> saveDomain(MarketplacePartnerDomain domain) async =>
      _marketplaceDomains[domain.id] = domain;
  @override
  Future<void> logSearch({
    required String? businessId,
    required String userId,
    required String query,
    required String source,
    required bool cacheHit,
    required int resultsCount,
    required int responseTimeMs,
  }) async {
    if (resultsCount == 0) {
      final normalized = query.trim().toLowerCase();
      final index = _marketplaceDemands.indexWhere(
        (item) =>
            item['businessId'] == businessId &&
            item['normalizedQuery'] == normalized,
      );
      if (index < 0) {
        _marketplaceDemands.add({
          'businessId': businessId,
          'query': query,
          'normalizedQuery': normalized,
          'searchCount': 1,
        });
      } else {
        _marketplaceDemands[index]['searchCount'] =
            (_marketplaceDemands[index]['searchCount'] as int) + 1;
      }
    }
  }

  @override
  Future<void> recordClick(MarketplaceClick click) async =>
      _marketplaceClicks[click.id] = click;
  @override
  Future<MarketplaceClick?> findClick(String id) async =>
      _marketplaceClicks[id];
  @override
  Future<void> updateClickStatus(
    String id,
    String status, {
    DateTime? redirectedAt,
  }) async {}
  @override
  Future<void> auditAdminAction({
    required String platformAdminId,
    required String action,
    required String entity,
    required String entityId,
    Map<String, dynamic>? beforeState,
    Map<String, dynamic>? afterState,
    String? reason,
    String? ipAddressHash,
  }) async {}
  @override
  Future<PublicBookingBusiness> ensurePublicBooking({
    required String businessId,
    required String businessName,
  }) async {
    final existing = _publicBookings.values
        .where((item) => item.businessId == businessId)
        .firstOrNull;
    if (existing != null) return existing;
    var base = PublicBookingSlug.normalize(businessName);
    if (base.length < 3 || PublicBookingSlug.reserved.contains(base)) {
      base = 'studio-${businessId.substring(0, businessId.length.clamp(1, 8))}';
    }
    var slug = base;
    var suffix = 2;
    while (_publicBookings.containsKey(slug)) {
      slug = '$base-${suffix++}';
    }
    final booking = PublicBookingBusiness(
      businessId: businessId,
      slug: slug,
      name: businessName,
      enabled: true,
    );
    _publicBookings[slug] = booking;
    return booking;
  }

  @override
  Future<PublicBookingBusiness?> findPublicBooking(String slug) async =>
      _publicBookings[slug];

  @override
  Future<List<Map<String, Object?>>> publicEntities({
    required String businessId,
    required String entity,
  }) async {
    return _records.entries
        .where(
          (entry) =>
              entry.key.startsWith('$businessId::$entity::') &&
              entry.value.payload['ativo'] != false &&
              entry.value.payload['ativo'] != 0,
        )
        .map(
          (entry) =>
              Map<String, Object?>.from(entry.value.payload)..removeWhere(
                (key, _) => !const {
                  'id',
                  'nome',
                  'preco',
                  'duracao_minutos',
                  'unidade_id',
                  'profissional_id',
                  'servico_id',
                  'horario_abertura',
                  'horario_fechamento',
                }.contains(key),
              ),
        )
        .toList();
  }

  @override
  Future<List<Map<String, Object?>>> publicSchedulingRecords({
    required String businessId,
    required Set<String> entities,
  }) async {
    return _records.entries
        .where(
          (entry) => entities.any(
            (entity) => entry.key.startsWith('$businessId::$entity::'),
          ),
        )
        .map((entry) {
          final parts = entry.key.split('::');
          return <String, Object?>{
            ...entry.value.payload,
            '_entity': parts[1],
            'id': entry.value.payload['id'] ?? parts[2],
          };
        })
        .toList();
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
  }) async {
    final idempotent = _publicIdempotency['$businessId::$idempotencyKey'];
    if (idempotent != null) return _publicAppointments[idempotent]!;
    final conflict = _publicAppointments.values.any(
      (item) =>
          item.businessId == businessId &&
          item.status != 'cancelado' &&
          item.professionalId == professionalId &&
          startsAt.isBefore(item.endsAt) &&
          endsAt.isAfter(item.startsAt),
    );
    if (conflict) {
      throw StateError(
        'HorÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¡rio indisponÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â­vel.',
      );
    }
    final phone = clientPhone.replaceAll(RegExp(r'D'), '');
    final found = _records.entries.where(
      (e) =>
          e.key.startsWith('$businessId::clientes::') &&
          (e.value.payload['whatsapp']?.toString().replaceAll(
                    RegExp(r'D'),
                    '',
                  ) ==
                  phone ||
              e.value.payload['telefone']?.toString().replaceAll(
                    RegExp(r'D'),
                    '',
                  ) ==
                  phone),
    );
    final clientId = found.isEmpty
        ? 'public_client_${tokenHash.substring(0, 20)}'
        : found.first.key.split('::').last;
    if (found.isEmpty) {
      _savePublicRecord(businessId, 'clientes', clientId, {
        'id': clientId,
        'comercio_id': businessId,
        'nome': clientName,
        'whatsapp': phone,
        'telefone': phone,
        'ativo': true,
        'data_cadastro': DateTime.now().toUtc().toIso8601String(),
      });
    }
    final mainId = 'public_appointment_${tokenHash.substring(0, 20)}';
    _savePublicRecord(businessId, 'agendamentos', mainId, {
      'id': mainId,
      'comercio_id': businessId,
      'unidade_id': unitId,
      'cliente_id': clientId,
      'profissional_id': professionalId,
      'servico_id': serviceId,
      'inicio': startsAt.toIso8601String(),
      'fim': endsAt.toIso8601String(),
      'origem': 'agendamento_publico',
      'status': 'agendado',
      'observacoes': notes,
      'excluido': 0,
    });
    final appointment = PublicAppointment(
      token: publicToken,
      businessId: businessId,
      serviceId: serviceId,
      professionalId: professionalId,
      startsAt: startsAt,
      endsAt: endsAt,
      status: 'agendado',
    );
    _publicAppointments[tokenHash] = appointment;
    _publicMainAppointments[tokenHash] = mainId;
    _publicIdempotency['$businessId::$idempotencyKey'] = tokenHash;
    return appointment;
  }

  @override
  Future<PublicAppointment?> findPublicAppointmentByIdempotency({
    required String businessId,
    required String idempotencyKey,
  }) async {
    final hash = _publicIdempotency['$businessId::$idempotencyKey'];
    return hash == null ? null : _publicAppointments[hash];
  }

  @override
  Future<PublicAppointment?> findPublicAppointment(String tokenHash) async =>
      _publicAppointments[tokenHash];

  @override
  Future<PublicAppointment?> updatePublicAppointment({
    required String tokenHash,
    required String status,
    DateTime? startsAt,
    DateTime? endsAt,
  }) async {
    final current = _publicAppointments[tokenHash];
    if (current == null) return null;
    final updated = PublicAppointment(
      token: current.token,
      businessId: current.businessId,
      serviceId: current.serviceId,
      professionalId: current.professionalId,
      startsAt: startsAt ?? current.startsAt,
      endsAt: endsAt ?? current.endsAt,
      status: status,
    );
    _publicAppointments[tokenHash] = updated;
    final mainId = _publicMainAppointments[tokenHash];
    if (mainId != null) {
      final key = _recordKey(current.businessId, 'agendamentos', mainId);
      final record = _records[key];
      if (record != null) {
        _savePublicRecord(current.businessId, 'agendamentos', mainId, {
          ...record.payload,
          'status': status,
          'inicio': updated.startsAt.toIso8601String(),
          'fim': updated.endsAt.toIso8601String(),
        });
      }
    }
    return updated;
  }

  void _savePublicRecord(
    String businessId,
    String entity,
    String id,
    Map<String, Object?> payload,
  ) {
    final key = _recordKey(businessId, entity, id);
    final version = (_records[key]?.version ?? 0) + 1;
    _records[key] = _SyncRecord(version, payload);
    final change = SyncChange(
      cursor: ++_cursor,
      entity: entity,
      entityId: id,
      serverVersion: version,
      deleted: false,
      payload: payload,
      updatedAt: DateTime.now().toUtc(),
    );
    _changes.add(_BusinessChange(businessId, change));
  }

  @override
  Future<void> close() async {}
}

final class _SyncRecord {
  final int version;
  final Map<String, Object?> payload;

  const _SyncRecord(this.version, this.payload);
}

final class _BusinessChange {
  final String businessId;
  final SyncChange change;

  const _BusinessChange(this.businessId, this.change);
}

final class _ResetRecord {
  final String userId;
  final String businessId;
  final DateTime expiresAt;

  const _ResetRecord({
    required this.userId,
    required this.businessId,
    required this.expiresAt,
  });
}
