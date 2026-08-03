class PublicBookingBusiness {
  final String businessId;
  final String slug;
  final String name;
  final bool enabled;
  final Map<String, Object?> profile;
  const PublicBookingBusiness({
    required this.businessId,
    required this.slug,
    required this.name,
    required this.enabled,
    this.profile = const {},
  });
  Map<String, Object?> toJson() => {
    'slug': slug,
    'name': name,
    'enabled': enabled,
    ...profile,
  };
}

class PublicAppointment {
  final String token;
  final String businessId;
  final String serviceId;
  final String? professionalId;
  final DateTime startsAt;
  final DateTime endsAt;
  final String status;
  const PublicAppointment({
    required this.token,
    required this.businessId,
    required this.serviceId,
    this.professionalId,
    required this.startsAt,
    required this.endsAt,
    required this.status,
  });
  Map<String, Object?> toJson() => {
    'token': token,
    'serviceId': serviceId,
    if (professionalId != null) 'professionalId': professionalId,
    'startsAt': startsAt.toUtc().toIso8601String(),
    'endsAt': endsAt.toUtc().toIso8601String(),
    'status': status,
  };
}

abstract interface class PublicBookingStore {
  Future<PublicBookingBusiness> ensurePublicBooking({
    required String businessId,
    required String businessName,
  });
  Future<PublicBookingBusiness?> findPublicBooking(String slug);
  Future<List<Map<String, Object?>>> publicEntities({
    required String businessId,
    required String entity,
  });
  Future<List<Map<String, Object?>>> publicSchedulingRecords({
    required String businessId,
    required Set<String> entities,
  });
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
  });
  Future<PublicAppointment?> findPublicAppointment(String tokenHash);
  Future<PublicAppointment?> findPublicAppointmentByIdempotency({
    required String businessId,
    required String idempotencyKey,
  });
  Future<PublicAppointment?> updatePublicAppointment({
    required String tokenHash,
    required String status,
    DateTime? startsAt,
    DateTime? endsAt,
  });
}

abstract final class PublicBookingSlug {
  static const reserved = {
    'api',
    'admin',
    'privacy',
    'politica-de-privacidade',
    'excluir-conta',
    'termos-de-uso',
    'contato',
    'login',
    'suporte',
    'agendar',
    'assets',
  };
  static String normalize(String value) {
    var result = value.trim().toLowerCase();
    const accents =
        '\u00e1\u00e0\u00e2\u00e3\u00e4\u00e9\u00e8\u00ea\u00eb\u00ed\u00ec\u00ee\u00ef\u00f3\u00f2\u00f4\u00f5\u00f6\u00fa\u00f9\u00fb\u00fc\u00e7\u00f1';
    const plain = 'aaaaaeeeeiiiiooooouuuucn';
    for (var i = 0; i < accents.length; i++) {
      result = result.replaceAll(accents[i], plain[i]);
    }
    result = result
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (result.length > 60) {
      result = result.substring(0, 60).replaceFirst(RegExp(r'-+$'), '');
    }
    return result;
  }
}
