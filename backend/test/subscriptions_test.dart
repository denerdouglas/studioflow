import 'package:test/test.dart';
import 'package:studioflow_backend/src/billing.dart';

void main() {
  group('Subscriptions - MockBillingVerifier', () {
    late MockBillingVerifier verifier;

    setUp(() {
      verifier = MockBillingVerifier();
    });

    test('Deve rejeitar token invalido e lancar excecao', () async {
      expect(
        () => verifier.verifyPurchase(
          purchaseToken: 'mock_invalid_token',
          packageName: 'com.studioflow.app',
          expectedObfuscatedAccountId: 'acc123',
          expectedObfuscatedProfileId: 'prof123',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('Deve processar token PENDING com estado pending', () async {
      final result = await verifier.verifyPurchase(
        purchaseToken: 'token_pending',
        packageName: 'com.studioflow.app',
        expectedObfuscatedAccountId: 'acc123',
        expectedObfuscatedProfileId: 'prof123',
      );
      expect(result['state'], equals('pending'));
      expect(result['offerId'], isNull);
    });

    test('Deve processar token ativo (nao-fundador) corretamente', () async {
      final result = await verifier.verifyPurchase(
        purchaseToken: 'token_valid',
        packageName: 'com.studioflow.app',
        expectedObfuscatedAccountId: 'acc123',
        expectedObfuscatedProfileId: 'prof123',
      );
      expect(result['state'], equals('active'));
      expect(result['offerId'], isNull);
      expect(result['autoRenewEnabled'], isTrue);
    });

    test('Deve processar token founder com trial_end_at preenchido', () async {
      final result = await verifier.verifyPurchase(
        purchaseToken: 'founder_valid_token',
        packageName: 'com.studioflow.app',
        expectedObfuscatedAccountId: 'acc123',
        expectedObfuscatedProfileId: 'prof123',
      );
      expect(result['state'], equals('active'));
      expect(result['offerId'], equals('founder_trial_20d'));
      expect(result['trialEndAt'], isNotNull);
    });
  });

  group('Subscriptions - Service Hashing', () {
    late SubscriptionService service;

    setUp(() {
      service = SubscriptionService(MockBillingVerifier(), 'test-secret');
    });

    test('generateObfuscatedId produz valor irreversivel e estavel', () {
      final id1 = service.generateObfuscatedId('1234');
      final id2 = service.generateObfuscatedId('1234');
      final id3 = service.generateObfuscatedId('5678');

      expect(id1, equals(id2)); // Stable
      expect(id1, isNot(equals('1234'))); // Obfuscated
      expect(id1, isNot(equals(id3))); // Unique per input
    });
    
    test('hashToken produz hash estavel do token', () {
      final hash1 = service.hashToken('token1');
      final hash2 = service.hashToken('token1');
      expect(hash1, equals(hash2));
    });
  });
}
