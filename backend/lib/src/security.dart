import 'dart:convert';
import 'dart:math';

import 'package:bcrypt/bcrypt.dart';
import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import 'models.dart';

final class PasswordSecurity {
  const PasswordSecurity();

  String hash(String password) {
    _validate(password);
    return BCrypt.hashpw(password, BCrypt.gensalt(logRounds: 12));
  }

  bool verify(String password, String hash) {
    try {
      return BCrypt.checkpw(password, hash);
    } on Object {
      return false;
    }
  }

  void _validate(String password) {
    if (password.length < 8 || password.length > 128) {
      throw ArgumentError('A senha deve possuir entre 8 e 128 caracteres.');
    }
  }
}

final class TokenSecurity {
  final String secret;
  final Duration accessDuration;
  final Random _random;

  TokenSecurity({
    required this.secret,
    required this.accessDuration,
    Random? random,
  }) : _random = random ?? Random.secure() {
    if (secret.length < 64) {
      throw ArgumentError('O segredo JWT deve possuir ao menos 64 caracteres.');
    }
  }

  String createAccessToken(AuthContext context) {
    return JWT(
      {
        'sub': context.userId,
        if (context.businessId != null) 'businessId': context.businessId,
        'role': context.role,
        'sessionId': context.sessionId,
        'type': 'access',
        'actorType': context.actorType,
        if (context.platformRole != null) 'platformRole': context.platformRole,
      },
      issuer: 'studioflow-api',
      audience: Audience.one('studioflow-app'),
    ).sign(
      SecretKey(secret),
      expiresIn: accessDuration,
      algorithm: JWTAlgorithm.HS256,
    );
  }

  AuthContext verifyAccessToken(String token) {
    final jwt = JWT.verify(
      token,
      SecretKey(secret),
      issuer: 'studioflow-api',
      audience: Audience.one('studioflow-app'),
    );
    final payload = Map<String, dynamic>.from(jwt.payload as Map);
    if (payload['type'] != 'access') {
      throw JWTException('Tipo de token invǭlido.');
    }
    return AuthContext(
      userId: payload['sub'] as String,
      businessId: payload['businessId'] as String?,
      role: payload['role'] as String,
      sessionId: payload['sessionId'] as String,
      actorType: payload['actorType'] as String? ?? 'tenant_user',
      platformRole: payload['platformRole'] as String?,
    );
  }

  String createOpaqueToken([int bytes = 48]) {
    final values = List<int>.generate(bytes, (_) => _random.nextInt(256));
    return base64UrlEncode(values).replaceAll('=', '');
  }

  String hashOpaqueToken(String token) =>
      sha256.convert(utf8.encode(token)).toString();
}
