import '../../../../core/network/api_client.dart';
import '../../domain/entities/driver_wallet.dart';

class DriverWalletRepository {
  const DriverWalletRepository({
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

  Future<DriverWallet> getWallet() async {
    final json = await _apiClient.get(
      '/api/v1/driver/wallet',
      headers: _authHeaders,
    );
    return DriverWallet.fromJson(json);
  }

  Future<List<WalletTransaction>> getTransactions() async {
    final json = await _apiClient.get(
      '/api/v1/driver/wallet/transactions',
      headers: _authHeaders,
    );
    final items = json['transactions'] as List<dynamic>? ?? const [];
    return items
        .whereType<Map>()
        .map((item) => WalletTransaction.fromJson(item.cast<String, dynamic>()))
        .toList();
  }

  Future<List<DriverPayout>> getPayouts() async {
    final json = await _apiClient.get(
      '/api/v1/driver/payouts',
      headers: _authHeaders,
    );
    final items = json['payouts'] as List<dynamic>? ?? const [];
    return items
        .whereType<Map>()
        .map((item) => DriverPayout.fromJson(item.cast<String, dynamic>()))
        .toList();
  }

  Future<List<DriverPayoutMethod>> getPayoutMethods() async {
    final json = await _apiClient.get(
      '/api/v1/driver/payout-methods',
      headers: _authHeaders,
    );
    final items = json['payout_methods'] as List<dynamic>? ?? const [];
    return items
        .whereType<Map>()
        .map(
            (item) => DriverPayoutMethod.fromJson(item.cast<String, dynamic>()))
        .toList();
  }

  Future<void> addPayoutMethod({
    required String type,
    required String providerRecipientId,
    required String maskedValue,
    required bool isDefault,
  }) async {
    await _apiClient.post(
      '/api/v1/driver/payout-methods',
      <String, dynamic>{
        'type': type,
        'provider_recipient_id': providerRecipientId,
        'masked_value': maskedValue,
        'is_default': isDefault,
      },
      headers: _authHeaders,
    );
  }

  Future<void> requestPayout(int amount) async {
    await _apiClient.post(
      '/api/v1/driver/payouts/request',
      <String, dynamic>{'amount': amount},
      headers: <String, String>{
        ...?_authHeaders,
        'Idempotency-Key':
            'driver-payout-$amount-${DateTime.now().millisecondsSinceEpoch}',
      },
    );
  }

  Future<DriverSubscriptionStatus> getSubscriptionStatus() async {
    final json = await _apiClient.get(
      '/api/v1/driver/subscription/status',
      headers: _authHeaders,
    );
    return DriverSubscriptionStatus.fromJson(json);
  }

  Future<String?> createSubscriptionPayment(String planId) async {
    final json = await _apiClient.post(
      '/api/v1/driver/subscription/payment',
      <String, dynamic>{'plan_id': planId},
      headers: _authHeaders,
    );
    final payment = json['payment'];
    if (payment is Map<String, dynamic>) {
      return payment['confirmation_url']?.toString();
    }
    return null;
  }
}
