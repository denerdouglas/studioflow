import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/domain/sincronizacao_backend.dart';

abstract interface class BackendTokenVault {
  Future<SessaoBackend?> read(String comercioId);
  Future<void> write(SessaoBackend session);
  Future<void> delete(String comercioId);
}

class SecureBackendTokenVault implements BackendTokenVault {
  final FlutterSecureStorage _storage;

  const SecureBackendTokenVault({this._storage = const FlutterSecureStorage()});

  String _key(String comercioId, String field) =>
      'studioflow.backend.$comercioId.$field';

  @override
  Future<SessaoBackend?> read(String comercioId) async {
    final values = await Future.wait([
      _storage.read(key: _key(comercioId, 'user')),
      _storage.read(key: _key(comercioId, 'access')),
      _storage.read(key: _key(comercioId, 'refresh')),
      _storage.read(key: _key(comercioId, 'refresh_expires')),
    ]);
    if (values.any((value) => value == null || value.isEmpty)) return null;
    final expiresAt = DateTime.tryParse(values[3]!);
    if (expiresAt == null) return null;
    return SessaoBackend(
      comercioId: comercioId,
      usuarioId: values[0]!,
      accessToken: values[1]!,
      refreshToken: values[2]!,
      refreshExpiraEm: expiresAt,
    );
  }

  @override
  Future<void> write(SessaoBackend session) async {
    await Future.wait([
      _storage.write(
        key: _key(session.comercioId, 'user'),
        value: session.usuarioId,
      ),
      _storage.write(
        key: _key(session.comercioId, 'access'),
        value: session.accessToken,
      ),
      _storage.write(
        key: _key(session.comercioId, 'refresh'),
        value: session.refreshToken,
      ),
      _storage.write(
        key: _key(session.comercioId, 'refresh_expires'),
        value: session.refreshExpiraEm.toUtc().toIso8601String(),
      ),
    ]);
  }

  @override
  Future<void> delete(String comercioId) async {
    await Future.wait([
      for (final field in const [
        'user',
        'access',
        'refresh',
        'refresh_expires',
      ])
        _storage.delete(key: _key(comercioId, field)),
    ]);
  }
}
