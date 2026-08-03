import 'package:postgres/postgres.dart';
import 'package:studioflow_backend/src/models.dart';
import 'package:studioflow_backend/src/billing.dart';
import 'package:studioflow_backend/src/postgres_store.dart';

class SubscriptionManager {
  final PostgresBackendStore _db;
  final SubscriptionService _service;

  SubscriptionManager(this._db, this._service);

  Future<void> verifyPurchase(
    String purchaseToken,
    String packageName,
    String userId,
    String businessId,
    String platform,
  ) async {
    final obfuscatedAccountId = _service.generateObfuscatedId(businessId);
    final obfuscatedProfileId = _service.generateObfuscatedId(userId);

    // This will throw if invalid or pending
    final result = await _service.verifier.verifyPurchase(
      purchaseToken: purchaseToken,
      packageName: packageName,
      expectedObfuscatedAccountId: obfuscatedAccountId,
      expectedObfuscatedProfileId: obfuscatedProfileId,
    );

    if (result['state'] == 'pending') {
      throw Exception('Purchase is still pending');
    }

    final purchaseTokenHash = _service.hashToken(purchaseToken);
    final purchaseTokenEncrypted = _service.encryptToken(purchaseToken);

    await _db.pool.execute(
      Sql.named('''
        INSERT INTO subscriptions (
          store_product_id, base_plan_id, offer_id,
          purchase_token_hash, purchase_token_encrypted,
          package_name, user_id, business_id, platform, state,
          trial_end_at, current_period_end_at, auto_renew_enabled,
          founder_price_locked, acquired_price_micros, currency_code,
          verification_source
        ) VALUES (
          @store_product_id, @base_plan_id, @offer_id,
          @purchase_token_hash, @purchase_token_encrypted,
          @package_name, @user_id, @business_id, @platform, @state,
          @trial_end_at, @current_period_end_at, @auto_renew_enabled,
          @founder_price_locked, @acquired_price_micros, @currency_code,
          @verification_source
        )
        ON CONFLICT (purchase_token_hash) DO UPDATE SET
          state = EXCLUDED.state,
          current_period_end_at = EXCLUDED.current_period_end_at,
          auto_renew_enabled = EXCLUDED.auto_renew_enabled,
          last_verified_at = NOW(),
          updated_at = NOW()
      '''),
      parameters: {
        'store_product_id': result['storeProductId'],
        'base_plan_id': result['basePlanId'],
        'offer_id': result['offerId'],
        'purchase_token_hash': purchaseTokenHash,
        'purchase_token_encrypted': purchaseTokenEncrypted,
        'package_name': packageName,
        'user_id': userId,
        'business_id': businessId,
        'platform': platform,
        'state': result['state'],
        'trial_end_at': result['trialEndAt'],
        'current_period_end_at': result['currentPeriodEndAt'],
        'auto_renew_enabled': result['autoRenewEnabled'] ?? false,
        'founder_price_locked': result['offerId'] == 'founder_trial_20d',
        'acquired_price_micros': result['acquiredPriceMicros'],
        'currency_code': result['currencyCode'],
        'verification_source': 'verifyPurchase',
      },
    );
  }

  Future<Entitlement> getEntitlement(String businessId) async {
    final result = await _db.pool.execute(
      Sql.named('''
        SELECT state, founder_price_locked, current_period_end_at
        FROM subscriptions
        WHERE business_id = @business_id
          AND state IN ('active', 'trial', 'grace_period')
        ORDER BY current_period_end_at DESC NULLS LAST
        LIMIT 1
      '''),
      parameters: {'business_id': businessId},
    );

    if (result.isEmpty) {
      return Entitlement(
        businessId: businessId,
        state: 'inactive',
        isFounder: false,
        issuedAt: DateTime.now().toUtc(),
        version: 1,
      );
    }

    final row = result.first;
    return Entitlement(
      businessId: businessId,
      state: row[0] as String,
      isFounder: row[1] as bool,
      issuedAt: DateTime.now().toUtc(),
      currentPeriodEndAt: row[2] as DateTime?,
      version: 1, // could be incremented based on events
    );
  }
}
