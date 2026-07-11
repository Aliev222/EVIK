import 'package:tow_truck_frontend/core/network/api_client.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver_earnings.dart';

class DriverEarningsRepository {
  const DriverEarningsRepository({
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

  Future<EarningsStats> getEarnings() async {
    final json = await _apiClient.get(
      '/api/v1/driver/earnings',
      headers: _authHeaders,
    );
    return EarningsStats.fromJson(json);
  }
}
