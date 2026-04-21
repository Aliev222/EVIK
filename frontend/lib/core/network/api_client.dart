abstract class ApiClient {
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body);
}

const defaultApiBaseUrl = String.fromEnvironment(
  'EVIK_API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8080',
);

class NoOpApiClient implements ApiClient {
  const NoOpApiClient();

  @override
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    // TODO: Replace with real HTTP client implementation.
    if (path == '/api/v1/orders') {
      final now = DateTime.now().millisecondsSinceEpoch.toString();
      return {
        'order': {
          'id': 'local-$now',
          'user_id': body['user_id'] ?? 'local-user',
          'pickup_lat': (body['pickup_lat'] as num?)?.toDouble() ?? 0.0,
          'pickup_lng': (body['pickup_lng'] as num?)?.toDouble() ?? 0.0,
          'dropoff_lat': (body['dropoff_lat'] as num?)?.toDouble() ?? 0.0,
          'dropoff_lng': (body['dropoff_lng'] as num?)?.toDouble() ?? 0.0,
          'status': 'searching',
          'driver_id': null,
        }
      };
    }
    return <String, dynamic>{};
  }
}
