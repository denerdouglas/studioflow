import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../services/billing/billing_gateway.dart';
import '../services/session_controller.dart';

class SubscriptionState {
  final bool isLoading;
  final String status;
  final String? errorMessage;
  final bool isFounder;
  final DateTime? validUntil;

  SubscriptionState({
    this.isLoading = false,
    this.status = 'inactive',
    this.errorMessage,
    this.isFounder = false,
    this.validUntil,
  });

  SubscriptionState copyWith({
    bool? isLoading,
    String? status,
    String? errorMessage,
    bool? isFounder,
    DateTime? validUntil,
  }) {
    return SubscriptionState(
      isLoading: isLoading ?? this.isLoading,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      isFounder: isFounder ?? this.isFounder,
      validUntil: validUntil ?? this.validUntil,
    );
  }
}

class SubscriptionController extends ChangeNotifier {
  final BillingGateway _billing;

  SubscriptionState _state = SubscriptionState();

  SubscriptionState get state => _state;

  SubscriptionController(this._billing) {
    _billing.purchaseStream.listen(_onPurchaseUpdate);
  }

  Future<void> fetchEntitlement() async {
    _state = _state.copyWith(isLoading: true, errorMessage: null);
    notifyListeners();

    try {
      // Simulação da consulta ao backend
      await Future.delayed(const Duration(milliseconds: 500));

      _state = _state.copyWith(isLoading: false, status: 'inactive');
    } catch (e) {
      _state = _state.copyWith(
        isLoading: false,
        errorMessage: 'Erro ao validar assinatura. Verifique sua conexão.',
      );
    }

    notifyListeners();
  }

  Future<void> buyPremium() async {
    _state = _state.copyWith(isLoading: true, errorMessage: null);
    notifyListeners();

    try {
      final isAvailable = await _billing.isAvailable;

      if (!isAvailable) {
        throw Exception('Loja não disponível.');
      }

      final products = await _billing.queryProductDetails({
        'studioflow_premium',
      });

      if (products.isEmpty) {
        throw Exception('Produto não encontrado.');
      }

      final product = products.first;

      final userId = SessionController.instance.usuario?.id ?? 'test_user';

      final businessId =
          SessionController.instance.usuario?.codigoComercio ?? 'test_business';

      await _billing.buyNonConsumable(
        productDetails: product,
        obfuscatedAccountId: businessId,
        obfuscatedProfileId: userId,
      );
    } catch (e) {
      _state = _state.copyWith(isLoading: false, errorMessage: e.toString());
      notifyListeners();
    }
  }

  Future<void> restorePurchases() async {
    _state = _state.copyWith(isLoading: true, errorMessage: null);
    notifyListeners();

    try {
      await _billing.restorePurchases();
    } catch (e) {
      _state = _state.copyWith(
        isLoading: false,
        errorMessage: 'Erro ao restaurar: $e',
      );
      notifyListeners();
    }
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) {
    for (final purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        _state = _state.copyWith(isLoading: true, status: 'pending');
        notifyListeners();
      } else if (purchaseDetails.status == PurchaseStatus.error) {
        _state = _state.copyWith(
          isLoading: false,
          errorMessage: purchaseDetails.error?.message ?? 'Erro na compra.',
        );
        notifyListeners();
      } else if (purchaseDetails.status == PurchaseStatus.purchased ||
          purchaseDetails.status == PurchaseStatus.restored) {
        _verifyPurchaseOnBackend(purchaseDetails);
      }
    }
  }

  Future<void> _verifyPurchaseOnBackend(PurchaseDetails purchaseDetails) async {
    try {
      final token = purchaseDetails.verificationData.serverVerificationData;

      if (token == 'mock_invalid_token') {
        throw Exception('Token inválido');
      }

      _state = _state.copyWith(
        isLoading: false,
        status: 'active',
        isFounder: token.contains('founder'),
      );

      await _billing.completePurchase(purchaseDetails);
    } catch (e) {
      _state = _state.copyWith(
        isLoading: false,
        errorMessage: 'Falha ao confirmar assinatura com o servidor.',
      );
    }

    notifyListeners();
  }
}
