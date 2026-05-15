import '../../../../core/network/api_client.dart';
import '../../domain/entities/payment_wallet.dart';

class PaymentRepository {
  const PaymentRepository({
    required ApiClient apiClient,
    required String? accessToken,
  })  : _apiClient = apiClient,
        _accessToken = accessToken;

  final ApiClient _apiClient;
  final String? _accessToken;

  Map<String, String>? get _authHeaders {
    final token = _accessToken;
    if (token == null || token.isEmpty) return null;
    return <String, String>{'Authorization': 'Bearer $token'};
  }

  Future<PaymentWallet> getWallet() async {
    final json = await _apiClient.get(
      '/api/v1/payments/wallet',
      headers: _authHeaders,
    );
    return PaymentWallet.fromJson(json);
  }

  Future<AddCardInitResponse> initAddCard() async {
    final json = await _apiClient.post(
      '/api/v1/client/payment-methods/init',
      const <String, dynamic>{},
      headers: _authHeaders,
    );
    return AddCardInitResponse.fromJson(json);
  }

  Future<OrderPayment> createOrderPayment({
    required String orderId,
    required String paymentMethod,
  }) async {
    final json = await _apiClient.post(
      '/api/v1/orders/$orderId/payments',
      <String, dynamic>{'payment_method': paymentMethod},
      headers: _authHeaders,
    );
    return OrderPayment.fromJson(json['payment'] as Map<String, dynamic>);
  }

  Future<OrderPayment> getOrderPaymentStatus(String orderId) async {
    final json = await _apiClient.get(
      '/api/v1/orders/$orderId/payment-status',
      headers: _authHeaders,
    );
    return OrderPayment.fromJson(json['payment'] as Map<String, dynamic>);
  }

  Future<OrderReceipt> getOrderReceipt(String orderId) async {
    final json = await _apiClient.get(
      '/api/v1/orders/$orderId/receipt',
      headers: _authHeaders,
    );
    return OrderReceipt.fromJson(json);
  }

  Future<PaymentCard> addCard(AddPaymentCardCommand command) async {
    throw UnsupportedError(
      'Direct card entry is disabled. Use initAddCard hosted YooKassa flow.',
    );
  }

  Future<PaymentCard> setDefaultCard(String cardId) async {
    final json = await _apiClient.post(
      '/api/v1/payments/cards/$cardId/default',
      const <String, dynamic>{},
      headers: _authHeaders,
    );
    return PaymentCard.fromJson(json['card'] as Map<String, dynamic>);
  }

  Future<void> deleteCard(String cardId) async {
    await _apiClient.delete(
      '/api/v1/payments/cards/$cardId',
      headers: _authHeaders,
    );
  }

  Future<AppliedPromocode> applyPromocode(String code) async {
    final json = await _apiClient.post(
      '/api/v1/payments/promocode/apply',
      <String, dynamic>{'code': code},
      headers: _authHeaders,
    );
    return AppliedPromocode.fromJson(
      json['promocode'] as Map<String, dynamic>,
    );
  }
}
