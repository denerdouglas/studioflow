import 'package:sqflite/sqflite.dart';

abstract final class BookingSlug {
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
    result = result.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    result = result.replaceAll(RegExp(r'^-+|-+$'), '');
    if (result.length > 60) {
      result = result.substring(0, 60).replaceFirst(RegExp(r'-+$'), '');
    }
    return result;
  }

  static bool valid(String value) {
    final normalized = normalize(value);
    return normalized == value &&
        value.length >= 3 &&
        !reserved.contains(value);
  }

  static Future<String> available(
    DatabaseExecutor db,
    String name, {
    String? exceptBusinessId,
  }) async {
    var base = normalize(name);
    if (base.length < 3 || reserved.contains(base)) base = 'studio-$base';
    var candidate = base;
    var suffix = 2;
    while (true) {
      final rows = await db.query(
        'comercios',
        columns: ['id'],
        where: exceptBusinessId == null
            ? 'booking_slug = ?'
            : 'booking_slug = ? AND id != ?',
        whereArgs: exceptBusinessId == null
            ? [candidate]
            : [candidate, exceptBusinessId],
        limit: 1,
      );
      if (rows.isEmpty) return candidate;
      candidate = '$base-${suffix++}';
    }
  }

  static String publicUrl(String slug) =>
      'https://studioflowapp.com.br/agendar/$slug';
}
