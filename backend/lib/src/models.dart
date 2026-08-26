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
  final String? bookingSlug;
  final bool? bookingEnabled;
  final bool moduloLojaAtivo;
  final bool moduloServicosAtivo;
  final String? segment;
  final String? moduleConfiguration;

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
    this.bookingSlug,
    this.bookingEnabled,
    this.moduloLojaAtivo = true,
    this.moduloServicosAtivo = true,
    this.segment,
    this.moduleConfiguration,
  });

  Map<String, Object?> toPublicJson() => {
    'userId': userId,
    'businessId': businessId,
    'businessName': businessName,
    'userName': userName,
    'phone': phone,
    'login': login,
    'role': role,
    'bookingSlug': bookingSlug,
    'bookingEnabled': bookingEnabled,
    'moduloLojaAtivo': moduloLojaAtivo,
    'moduloServicosAtivo': moduloServicosAtivo,
    'segment': segment,
    'moduleConfiguration': moduleConfiguration,
  };
}

final class AuthContext {
  final String userId;
  final String?
  businessId; // Can be null for platform_admins if they are global
  final String role;
  final String sessionId;
  final String actorType; // e.g. 'tenant_user', 'platform_admin'
  final String? platformRole; // e.g. 'platform_super_admin'

  const AuthContext({
    required this.userId,
    this.businessId,
    required this.role,
    required this.sessionId,
    this.actorType = 'tenant_user',
    this.platformRole,
  });

  bool get isPlatformAdmin => actorType == 'platform_admin';
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

final class SubscriptionRecord {
  final String id;
  final String storeProductId;
  final String basePlanId;
  final String? offerId;
  final String purchaseTokenHash;
  final String purchaseTokenEncrypted;
  final String? linkedPurchaseTokenHash;
  final String packageName;
  final String userId;
  final String businessId;
  final String platform;
  final String state;
  final DateTime? trialEndAt;
  final DateTime? currentPeriodEndAt;
  final bool autoRenewEnabled;
  final bool founderPriceLocked;
  final int? acquiredPriceMicros;
  final String? currencyCode;
  final DateTime? lastVerifiedAt;
  final String verificationSource;
  final DateTime? acknowledgedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SubscriptionRecord({
    required this.id,
    required this.storeProductId,
    required this.basePlanId,
    this.offerId,
    required this.purchaseTokenHash,
    required this.purchaseTokenEncrypted,
    this.linkedPurchaseTokenHash,
    required this.packageName,
    required this.userId,
    required this.businessId,
    required this.platform,
    required this.state,
    this.trialEndAt,
    this.currentPeriodEndAt,
    required this.autoRenewEnabled,
    required this.founderPriceLocked,
    this.acquiredPriceMicros,
    this.currencyCode,
    this.lastVerifiedAt,
    required this.verificationSource,
    this.acknowledgedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'storeProductId': storeProductId,
    'basePlanId': basePlanId,
    if (offerId != null) 'offerId': offerId,
    'userId': userId,
    'businessId': businessId,
    'platform': platform,
    'state': state,
    if (trialEndAt != null) 'trialEndAt': trialEndAt!.toIso8601String(),
    if (currentPeriodEndAt != null)
      'currentPeriodEndAt': currentPeriodEndAt!.toIso8601String(),
    'autoRenewEnabled': autoRenewEnabled,
    'founderPriceLocked': founderPriceLocked,
  };
}

final class Entitlement {
  final String businessId;
  final String state;
  final bool isFounder;
  final DateTime issuedAt;
  final DateTime? currentPeriodEndAt;
  final int version;

  const Entitlement({
    required this.businessId,
    required this.state,
    required this.isFounder,
    required this.issuedAt,
    this.currentPeriodEndAt,
    required this.version,
  });

  Map<String, Object?> toJson() => {
    'businessId': businessId,
    'state': state,
    'isFounder': isFounder,
    'issuedAt': issuedAt.toIso8601String(),
    if (currentPeriodEndAt != null)
      'currentPeriodEndAt': currentPeriodEndAt!.toIso8601String(),
    'version': version,
  };
}
