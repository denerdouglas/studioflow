final class PlatformAdmin {
  final String id;
  final String userId;
  final String role;
  final bool active;
  final Map<String, dynamic> permissions;
  final DateTime createdAt;

  const PlatformAdmin({
    required this.id,
    required this.userId,
    required this.role,
    required this.active,
    required this.permissions,
    required this.createdAt,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'userId': userId,
    'role': role,
    'active': active,
    'permissions': permissions,
    'createdAt': createdAt.toIso8601String(),
  };
}

abstract interface class AdminBackendStore {
  Future<PlatformAdmin?> findPlatformAdminByUserId(String userId);
}
