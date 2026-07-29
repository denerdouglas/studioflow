import 'package:studioflow_backend/studioflow_backend.dart';
import 'package:test/test.dart';

void main() {
  const secret =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

  test('senha usa hash BCrypt e não aceita senha curta', () {
    const security = PasswordSecurity();
    final hash = security.hash('senha-segura-123');
    expect(hash, startsWith(r'$2'));
    expect(hash, isNot(contains('senha-segura-123')));
    expect(security.verify('senha-segura-123', hash), isTrue);
    expect(security.verify('senha-incorreta', hash), isFalse);
    expect(() => security.hash('curta'), throwsArgumentError);
  });

  test('JWT mantém comércio, usuário, sessão e rejeita segredo curto', () {
    final security = TokenSecurity(
      secret: secret,
      accessDuration: const Duration(minutes: 15),
    );
    const context = AuthContext(
      userId: 'usuario-a',
      businessId: 'comercio-a',
      role: 'dono',
      sessionId: 'sessao-a',
    );
    final decoded = security.verifyAccessToken(
      security.createAccessToken(context),
    );
    expect(decoded.userId, context.userId);
    expect(decoded.businessId, context.businessId);
    expect(decoded.sessionId, context.sessionId);
    expect(
      () => TokenSecurity(
        secret: 'curto',
        accessDuration: const Duration(minutes: 15),
      ),
      throwsArgumentError,
    );
  });
}
