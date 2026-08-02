import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';

abstract class BillingGateway {
  Stream<List<PurchaseDetails>> get purchaseStream;
  
  Future<bool> get isAvailable;
  
  Future<List<ProductDetails>> queryProductDetails(Set<String> productIds);
  
  Future<bool> buyNonConsumable({required ProductDetails productDetails, required String obfuscatedAccountId, required String obfuscatedProfileId});
  
  Future<void> restorePurchases();
  
  Future<void> completePurchase(PurchaseDetails purchaseDetails);
}
