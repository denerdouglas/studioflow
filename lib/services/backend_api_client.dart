import 'dart:convert';

import 'package:http/http.dart' as http;

class BackendHttpException implements Exception {
  final int statusCode;
  final String code;
  final String message;

  const BackendHttpException(this.statusCode, this.code, this.message);

  @override
  String toString() => message;
}

class BackendApiClient {
  final http.Client _client;

  BackendApiClient({http.Client? client}) : _client = client ?? http.Client();

  Uri normalizeEndpoint(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw const FormatException('Endpoint do backend inválido.');
    }

    final local = const {'localhost', '127.0.0.1', '::1'}.contains(uri.host);

    if (uri.scheme != 'https' && !(uri.scheme == 'http' && local)) {
      throw const FormatException(
        'O backend deve utilizar HTTPS. HTTP é aceito apenas localmente.',
      );
    }

    return uri.replace(path: uri.path.replaceAll(RegExp(r'/$'), ''));
  }

  Future<Map<String, dynamic>> registerBusiness({
    required Uri endpoint,
    required String businessId,
    required String businessName,
    required String segment,
    required String userId,
    required String ownerName,
    required String phone,
    required String login,
    required String password,
  }) {
    return _post(
      endpoint,
      '/v1/auth/register-business',
      {
        'businessId': businessId,
        'businessName': businessName,
        'segment': segment,
        'userId': userId,
        'ownerName': ownerName,
        'phone': phone,
        'login': login,
        'password': password,
      },
    );
  }

  Future<Map<String, dynamic>> login({
    required Uri endpoint,
    required String login,
    required String password,
    String? businessId,
  }) {
    return _post(
      endpoint,
      '/v1/auth/login',
      {
        'login': login,
        'password': password,
        'businessId': businessId,
      },
    );
  }

  Future<Map<String, dynamic>> refresh({
    required Uri endpoint,
    required String refreshToken,
  }) {
    return _post(
      endpoint,
      '/v1/auth/refresh',
      {'refreshToken': refreshToken},
    );
  }

  Future<Map<String, dynamic>> push({
    required Uri endpoint,
    required String accessToken,
    required List<Map<String, Object?>> operations,
  }) {
    return _post(
      endpoint,
      '/v1/sync/push',
      {'operations': operations},
      accessToken: accessToken,
    );
  }

  Future<Map<String, dynamic>> pull({
    required Uri endpoint,
    required String accessToken,
    required int cursor,
    int limit = 200,
  }) {
    return _get(
      endpoint,
      '/v1/sync/pull',
      {
        'cursor': '$cursor',
        'limit': '$limit',
      },
      accessToken: accessToken,
    );
  }

  Future<Map<String, dynamic>> catalogGtin({
    required Uri endpoint,
    required String accessToken,
    required String gtin,
  }) {
    return _get(
      endpoint,
      '/v1/catalog/gtin/$gtin',
      const {},
      accessToken: accessToken,
    );
  }

  Future<Map<String, dynamic>> messagesHistory({
    required Uri endpoint,
    required String accessToken,
    int limit = 100,
  }) {
    return _get(
      endpoint,
      '/v1/messages/history',
      {'limit': '${limit.clamp(1, 500)}'},
      accessToken: accessToken,
    );
  }

  Future<Map<String, dynamic>> _post(
    Uri endpoint,
    String path,
    Map<String, Object?> body, {
    String? accessToken,
  }) async {
    final response = await _client
        .post(
          _resolve(endpoint, path),
          headers: {
            'content-type': 'application/json',
            if (accessToken != null) 'authorization': 'Bearer $accessToken',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));

    return _decode(response);
  }

  Future<Map<String, dynamic>> _get(
    Uri endpoint,
    String path,
    Map<String, String> query, {
    required String accessToken,
  }) async {
    final response = await _client
        .get(
          _resolve(endpoint, path).replace(queryParameters: query),
          headers: {'authorization': 'Bearer $accessToken'},
        )
        .timeout(const Duration(seconds: 30));

    return _decode(response);
  }

  Uri _resolve(Uri endpoint, String path) {
    final prefix = endpoint.path == '/' ? '' : endpoint.path;
    return endpoint.replace(path: '$prefix$path');
  }

  Map<String, dynamic> _decode(http.Response response) {
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(
            jsonDecode(response.body) as Map,
          );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['error'];
      final map = error is Map
          ? Map<String, dynamic>.from(error)
          : const <String, dynamic>{};

      throw BackendHttpException(
        response.statusCode,
        map['code'] as String? ?? 'http_error',
        map['message'] as String? ??
            'Backend respondeu ${response.statusCode}.',
      );
    }

    return decoded;
  }
}
