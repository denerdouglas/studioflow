import 'package:sqflite/sqflite.dart';

import '../core/utils/booking_slug.dart';
import '../database/database_service.dart';
import '../services/session_controller.dart';

class BookingSettings {
  final String slug;
  final bool enabled;
  const BookingSettings({required this.slug, required this.enabled});
  String get publicUrl => BookingSlug.publicUrl(slug);
}

class BookingSettingsRepository {
  final Future<Database> Function() _databaseProvider;
  BookingSettingsRepository({Future<Database> Function()? databaseProvider})
    : _databaseProvider =
          databaseProvider ?? (() => DatabaseService.instance.database);

  String get _businessId => SessionController.instance.usuario!.comercioId;

  Future<BookingSettings> load() async {
    final db = await _databaseProvider();
    final rows = await db.query(
      'comercios',
      columns: ['booking_slug', 'booking_enabled', 'nome'],
      where: 'id = ?',
      whereArgs: [_businessId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Estabelecimento não encontrado.');
    var slug = rows.single['booking_slug'] as String?;
    if (slug == null || slug.isEmpty) {
      slug = '';
    }
    return BookingSettings(
      slug: slug,
      enabled: (rows.single['booking_enabled'] as num? ?? 1) == 1,
    );
  }

  Future<BookingSettings> update({
    required String slug,
    required bool enabled,
  }) async {
    final db = await _databaseProvider();
    final normalized = BookingSlug.normalize(slug);
    if (!BookingSlug.valid(normalized)) {
      throw StateError('Endereço inválido ou reservado.');
    }
    final available = await BookingSlug.available(
      db,
      normalized,
      exceptBusinessId: _businessId,
    );
    if (available != normalized) {
      throw StateError('Este endereço já está em uso.');
    }
    final current = await load();
    if (current.slug != normalized) {
      await db.insert('booking_slug_aliases', {
        'slug': current.slug,
        'comercio_id': _businessId,
        'criado_em': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await _save(db, normalized, enabled);
    return BookingSettings(slug: normalized, enabled: enabled);
  }

  Future<void> _save(Database db, String slug, bool enabled) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'comercios',
      {
        'booking_slug': slug,
        'booking_enabled': enabled ? 1 : 0,
        'booking_public_url': BookingSlug.publicUrl(slug),
        'booking_created_at': now,
        'booking_updated_at': now,
        'atualizado_em': now,
      },
      where: 'id = ?',
      whereArgs: [_businessId],
    );
  }
}
