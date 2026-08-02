import 'dart:io';
import 'package:postgres/postgres.dart';

class DatabaseConfig {
  static SslMode get _sslMode {
    final mode = Platform.environment['DATABASE_SSL_MODE'];
    switch (mode?.toLowerCase()) {
      case 'disable':
        return SslMode.disable;
      case 'require':
        return SslMode.require;
      case 'verifyfull':
        return SslMode.verifyFull;
      default:
        // Mantém require como padrão seguro, mas permite override
        return SslMode.require;
    }
  }

  static Endpoint _parseUrl(String url) {
    final uri = Uri.parse(url);
    if (uri.scheme != 'postgres' && uri.scheme != 'postgresql') {
      throw FormatException('Invalid database URL scheme: ${uri.scheme}');
    }

    String? username;
    String? password;
    if (uri.userInfo.isNotEmpty) {
      final parts = uri.userInfo.split(':');
      username = Uri.decodeComponent(parts[0]);
      if (parts.length > 1) {
        password = Uri.decodeComponent(parts[1]);
      }
    }

    final database = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : 'postgres';

    return Endpoint(
      host: uri.host,
      port: uri.hasPort ? uri.port : 5432,
      database: database,
      username: username,
      password: password,
    );
  }

  static Pool createPool(String url) {
    final endpoint = _parseUrl(url);
    return Pool.withEndpoints(
      [endpoint],
      settings: PoolSettings(
        sslMode: _sslMode,
      ),
    );
  }

  static Future<Connection> createConnection(String url) {
    final endpoint = _parseUrl(url);
    return Connection.open(
      endpoint,
      settings: ConnectionSettings(
        sslMode: _sslMode,
      ),
    );
  }
}
