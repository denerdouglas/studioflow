import 'models.dart';

abstract interface class BackendStore {
  Future<void> ping();

  Future<AccountIdentity> createBusinessOwner({
    required String businessId,
    required String businessName,
    required String segment,
    required String userId,
    required String ownerName,
    required String phone,
    required String login,
    required String passwordHash,
  });

  Future<List<AccountIdentity>> findAccountsByLogin(String normalizedLogin);
  Future<AccountIdentity?> findAccount(String userId, String businessId);

  Future<void> createSession(SessionRecord session);
  Future<SessionRecord?> findSessionByRefreshHash(String refreshHash);
  Future<void> rotateSession({
    required String sessionId,
    required String refreshHash,
    required DateTime expiresAt,
  });
  Future<void> revokeSession(String sessionId);

  Future<void> audit({
    required String event,
    String? businessId,
    String? userId,
    String? sessionId,
    required bool success,
    required Map<String, Object?> details,
  });

  Future<List<SyncResult>> applyMutations({
    required AuthContext actor,
    required List<SyncMutation> mutations,
  });

  Future<List<SyncChange>> pullChanges({
    required String businessId,
    required int afterCursor,
    required int limit,
  });

  Future<void> createPasswordReset({
    required String id,
    required String userId,
    required String businessId,
    required String tokenHash,
    required String channel,
    required DateTime expiresAt,
  });

  Future<AccountIdentity?> consumePasswordReset({
    required String tokenHash,
    required String newPasswordHash,
  });

  Future<void> close();
}
