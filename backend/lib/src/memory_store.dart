import 'models.dart';
import 'marketplace.dart';
import 'store.dart';
import 'admin.dart';


final class MemoryBackendStore
    implements BackendStore, MarketplaceBackendStore, AdminBackendStore {
  final Map<String, AccountIdentity> _accounts = {};
  final Map<String, SessionRecord> _sessions = {};
  final Map<String, _ResetRecord> _resets = {};
  final Map<String, _SyncRecord> _records = {};
  final Map<String, SyncResult> _operations = {};
  final List<_BusinessChange> _changes = [];
  final List<Map<String, Object?>> audits = [];
  int _cursor = 0;

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
  Future<PlatformAdmin?> findPlatformAdminByUserId(String userId) async => null;

  @override
  Future<List<MarketplacePartner>> listActivePartners() async => [];
  @override
  Future<List<MarketplacePartner>> listAllPartners() async => [];
  @override
  Future<MarketplacePartner?> findPartnerById(String id) async => null;
  @override
  Future<void> savePartner(MarketplacePartner partner) async {}
  @override
  Future<List<MarketplacePartnerDomain>> listDomainsForPartner(String partnerId) async => [];
  @override
  Future<void> saveDomain(MarketplacePartnerDomain domain) async {}
  @override
  Future<void> logSearch({required String? businessId, required String userId, required String query, required String source, required bool cacheHit, required int resultsCount, required int responseTimeMs}) async {}
  @override
  Future<void> recordClick(MarketplaceClick click) async {}
  @override
  Future<MarketplaceClick?> findClick(String id) async => null;
  @override
  Future<void> updateClickStatus(String id, String status, {DateTime? redirectedAt}) async {}
  @override
  Future<void> auditAdminAction({required String platformAdminId, required String action, required String entity, required String entityId, Map<String, dynamic>? beforeState, Map<String, dynamic>? afterState, String? reason, String? ipAddressHash}) async {}
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
