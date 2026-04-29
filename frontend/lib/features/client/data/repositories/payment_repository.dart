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

  Future<PaymentCard> addCard(AddPaymentCardCommand command) async {
    final json = await _apiClient.post(
      '/api/v1/payments/cards',
      <String, dynamic>{
        'card_number': command.cardNumber,
        'exp_month': command.expMonth,
        'exp_year': command.expYear,
        'holder': command.holder,
        'cvv': command.cvv,
        'set_default': command.setDefault,
      },
      headers: _authHeaders,
    );
    return PaymentCard.fromJson(json['card'] as Map<String, dynamic>);
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
