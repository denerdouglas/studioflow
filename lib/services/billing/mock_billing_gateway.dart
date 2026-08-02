import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'billing_gateway.dart';

class MockBillingGateway implements BillingGateway {
  final StreamController<List<PurchaseDetails>> _purchaseStreamController = StreamController.broadcast();

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _purchaseStreamController.stream;

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<List<ProductDetails>> queryProductDetails(Set<String> productIds) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return productIds.map((id) => MockProductDetails(
      id: id,
      title: 'Plano Fundador StudioFlow',
      description: 'Acesso completo',
      price: 'R\$ 14,90',
      rawPrice: 14.90,
      currencyCode: 'BRL',
    )).toList();
  }

  @override
  Future<bool> buyNonConsumable({
    required ProductDetails productDetails,
    required String obfuscatedAccountId,
    required String obfuscatedProfileId,
  }) async {
    // Simular fluxo de compra com delay
    Future.delayed(const Duration(seconds: 1), () {
      final purchase = MockPurchaseDetails(
        productID: productDetails.id,
        purchaseID: 'mock_purchase_id_${DateTime.now().millisecondsSinceEpoch}',
        transactionDate: DateTime.now().millisecondsSinceEpoch.toString(),
        status: PurchaseStatus.purchased,
        verificationData: PurchaseVerificationData(
          localVerificationData: 'mock_local',
          serverVerificationData: 'founder_valid_token', // token for backend mock
          source: 'mock_store',
        ),
      );
      _purchaseStreamController.add([purchase]);
    });
    return true;
  }

  @override
  Future<void> restorePurchases() async {
    Future.delayed(const Duration(seconds: 1), () {
      final purchase = MockPurchaseDetails(
        productID: 'studioflow_premium',
        purchaseID: 'mock_restored_id',
        transactionDate: DateTime.now().millisecondsSinceEpoch.toString(),
        status: PurchaseStatus.restored,
        verificationData: PurchaseVerificationData(
          localVerificationData: 'mock_local',
          serverVerificationData: 'founder_valid_token',
          source: 'mock_store',
        ),
      );
      _purchaseStreamController.add([purchase]);
    });
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchaseDetails) async {
    // Mock
  }
}

class MockProductDetails extends ProductDetails {
  MockProductDetails({
    required super.id,
    required super.title,
    required super.description,
    required super.price,
    required super.rawPrice,
    required super.currencyCode,
  });
}

class MockPurchaseDetails extends PurchaseDetails {
  MockPurchaseDetails({
    required super.productID,
    required super.purchaseID,
    required super.transactionDate,
    required super.status,
    required super.verificationData,
  });
}
