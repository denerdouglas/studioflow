import 'dart:convert';
import 'package:crypto/crypto.dart';

abstract class BillingVerifier {
  /// Retorna o entitlement associado a um purchaseToken verificado e validado
  Future<Map<String, Object?>> verifyPurchase({
    required String purchaseToken,
    required String packageName,
    required String expectedObfuscatedAccountId,
    required String expectedObfuscatedProfileId,
  });

  /// Retorna os detalhes atualizados de uma assinatura para processamento RTDN ou Sync
  Future<Map<String, Object?>> getSubscriptionInfo(String purchaseToken);
}

class MockBillingVerifier implements BillingVerifier {
  @override
  Future<Map<String, Object?>> verifyPurchase({
    required String purchaseToken,
    required String packageName,
    required String expectedObfuscatedAccountId,
    required String expectedObfuscatedProfileId,
  }) async {
    // Para testes seguros com mock
    if (purchaseToken == 'mock_invalid_token') {
      throw Exception('Mock: Token inválido');
    }

    final bool isFounder = purchaseToken.contains('founder');
    final bool isPending = purchaseToken.contains('pending');

    return {
      'state': isPending ? 'pending' : 'active',
      'storeProductId': 'studioflow_premium',
      'basePlanId': 'monthly',
      'offerId': isFounder ? 'founder_trial_20d' : null,
      'trialEndAt': isFounder
          ? DateTime.now().add(const Duration(days: 20)).toUtc()
          : null,
      'currentPeriodEndAt': DateTime.now()
          .add(const Duration(days: 30))
          .toUtc(),
      'autoRenewEnabled': true,
      'acquiredPriceMicros': 14900000,
      'currencyCode': 'BRL',
    };
  }

  @override
  Future<Map<String, Object?>> getSubscriptionInfo(String purchaseToken) async {
    // Simulando retorno da Google Play Developer API
    return {
      'state': 'active',
      'currentPeriodEndAt': DateTime.now()
          .add(const Duration(days: 30))
          .toUtc(),
    };
  }
}

class GooglePlayVerifier implements BillingVerifier {
  // Em produção, isso usará credenciais GCP via package googleapis

  @override
  Future<Map<String, Object?>> verifyPurchase({
    required String purchaseToken,
    required String packageName,
    required String expectedObfuscatedAccountId,
    required String expectedObfuscatedProfileId,
  }) async {
    // Placeholder para a chamada real ao purchases.subscriptionsv2.get
    throw UnimplementedError(
      'Configurar as credenciais do Google Cloud primeiro.',
    );
  }

  @override
  Future<Map<String, Object?>> getSubscriptionInfo(String purchaseToken) async {
    throw UnimplementedError(
      'Configurar as credenciais do Google Cloud primeiro.',
    );
  }
}

class SubscriptionService {
  final BillingVerifier verifier;
  final String _hmacSecret;

  SubscriptionService(this.verifier, this._hmacSecret);

  String hashToken(String token) {
    final bytes = utf8.encode(token);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  String encryptToken(String token) {
    // Dummy encryption for now
    return base64Encode(utf8.encode(token));
  }

  String generateObfuscatedId(String rawId) {
    final hmac = Hmac(sha256, utf8.encode(_hmacSecret));
    final digest = hmac.convert(utf8.encode(rawId));
    return digest.toString();
  }

  // A ser expandido com injecao do DB para validacao completa
}
