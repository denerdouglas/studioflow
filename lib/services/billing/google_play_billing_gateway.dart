import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'billing_gateway.dart';

class GooglePlayBillingGateway implements BillingGateway {
  final InAppPurchase _iap = InAppPurchase.instance;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _iap.purchaseStream;

  @override
  Future<bool> get isAvailable => _iap.isAvailable();

  @override
  Future<List<ProductDetails>> queryProductDetails(Set<String> productIds) async {
    final response = await _iap.queryProductDetails(productIds);
    return response.productDetails;
  }

  @override
  Future<bool> buyNonConsumable({
    required ProductDetails productDetails,
    required String obfuscatedAccountId,
    required String obfuscatedProfileId,
  }) async {
    final purchaseParam = GooglePlayPurchaseParam(
      productDetails: productDetails,
      applicationUserName: obfuscatedAccountId,
      // Note: In older versions obfuscatedProfileId is part of a different param or handled by the backend.
      // We pass what we can via GooglePlayPurchaseParam.
    );
    return _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  @override
  Future<void> restorePurchases() async {
    await _iap.restorePurchases();
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchaseDetails) async {
    if (purchaseDetails.pendingCompletePurchase) {
      await _iap.completePurchase(purchaseDetails);
    }
  }
}
