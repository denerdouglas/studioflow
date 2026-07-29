final class AccountIdentity {
  final String userId;
  final String businessId;
  final String businessName;
  final String userName;
  final String phone;
  final String login;
  final String role;
  final String passwordHash;
  final bool active;

  const AccountIdentity({
    required this.userId,
    required this.businessId,
    required this.businessName,
    required this.userName,
    required this.phone,
    required this.login,
    required this.role,
    required this.passwordHash,
    required this.active,
  });

  Map<String, Object?> toPublicJson() => {
    'userId': userId,
    'businessId': businessId,
    'businessName': businessName,
    'userName': userName,
    'phone': phone,
    'login': login,
    'role': role,
  };
}

final class AuthContext {
  final String userId;
  final String businessId;
  final String role;
  final String sessionId;

  const AuthContext({
    required this.userId,
    required this.businessId,
    required this.role,
    required this.sessionId,
  });
}

final class SessionRecord {
  final String id;
  final String userId;
  final String businessId;
  final String refreshTokenHash;
  final DateTime expiresAt;
  final bool revoked;

  const SessionRecord({
    required this.id,
    required this.userId,
    required this.businessId,
    required this.refreshTokenHash,
    required this.expiresAt,
    required this.revoked,
  });
}

final class SyncMutation {
  final String operationId;
  final String entity;
  final String entityId;
  final String operation;
  final int localVersion;
  final Map<String, Object?> payload;

  const SyncMutation({
    required this.operationId,
    required this.entity,
    required this.entityId,
    required this.operation,
    required this.localVersion,
    required this.payload,
  });
}

final class SyncResult {
  final String operationId;
  final String status;
  final int serverVersion;
  final Map<String, Object?>? serverPayload;

  const SyncResult({
    required this.operationId,
    required this.status,
    required this.serverVersion,
    this.serverPayload,
  });

  Map<String, Object?> toJson() => {
    'operationId': operationId,
    'status': status,
    'serverVersion': serverVersion,
    if (serverPayload != null) 'serverPayload': serverPayload,
  };
}

final class SyncChange {
  final int cursor;
  final String entity;
  final String entityId;
  final int serverVersion;
  final bool deleted;
  final Map<String, Object?> payload;
  final DateTime updatedAt;

  const SyncChange({
    required this.cursor,
    required this.entity,
    required this.entityId,
    required this.serverVersion,
    required this.deleted,
    required this.payload,
    required this.updatedAt,
  });

  Map<String, Object?> toJson() => {
    'cursor': cursor,
    'entity': entity,
    'entityId': entityId,
    'serverVersion': serverVersion,
    'deleted': deleted,
    'payload': payload,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
}
