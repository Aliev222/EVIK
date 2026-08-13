import 'package:tow_truck_frontend/core/network/api_client.dart';

/// Deletes the caller's own account via DELETE /api/v1/account.
class AccountRepository {
  const AccountRepository({
    required ApiClient apiClient,
    required String? accessToken,
    String? Function()? accessTokenProvider,
  })  : _apiClient = apiClient,
        _accessToken = accessToken,
        _accessTokenProvider = accessTokenProvider;

  final ApiClient _apiClient;
  final String? _accessToken;
  final String? Function()? _accessTokenProvider;

  Map<String, String>? get _authHeaders {
    final token = _accessTokenProvider?.call() ?? _accessToken;
    if (token == null || token.isEmpty) return null;
    return <String, String>{'Authorization': 'Bearer $token'};
  }

  Future<void> deleteAccount() async {
    await _apiClient.delete('/api/v1/account', headers: _authHeaders);
  }
}