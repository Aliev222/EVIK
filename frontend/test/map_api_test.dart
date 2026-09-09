import 'package:flutter_test/flutter_test.dart';
import 'package:tow_truck_frontend/core/network/api_client.dart';
import 'package:tow_truck_frontend/core/services/map_api.dart';

class _FakeApiClient implements ApiClient {
  Map<String, dynamic> response = <String, dynamic>{};
  String? lastPath;
  Map<String, String>? lastHeaders;

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? headers,
  }) async {
    lastPath = path;
    lastHeaders = headers;
    return response;
  }

  @override
  Future<Map<String, dynamic>> delete(String path,
          {Map<String, String>? headers}) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body,
          {Map<String, String>? headers}) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body,
          {Map<String, String>? headers}) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body,
          {Map<String, String>? headers}) =>
      throw UnimplementedError();
}

void main() {
  test('search uses backend geocoding endpoint and parses first result',
      () async {
    final client = _FakeApiClient()
      ..response = <String, dynamic>{
        'results': <Map<String, dynamic>>[
          <String, dynamic>{
            'display_name': 'ул. Пушкина, Махачкала',
            'lat': 42.984,
            'lng': 47.505,
          },
        ],
      };
    final api = MapApi(apiClient: client, accessTokenProvider: () => null);

    final result = await api.geocode('ул. Пушкина');

    expect(client.lastPath, contains('/api/v1/geocode/search?'));
    expect(client.lastPath, contains('limit=1'));
    expect(result?.address, 'ул. Пушкина, Махачкала');
    expect(result?.latitude, 42.984);
    expect(result?.longitude, 47.505);
  });

  test('route preview is authenticated and parses backend response', () async {
    final client = _FakeApiClient()
      ..response = <String, dynamic>{
        'points': <Map<String, dynamic>>[
          <String, dynamic>{'lat': 42.98, 'lng': 47.50},
          <String, dynamic>{'lat': 42.99, 'lng': 47.51},
        ],
        'distanceMeters': 1200.0,
        'durationSeconds': 300,
      };
    final api = MapApi(
      apiClient: client,
      accessTokenProvider: () => 'access-token',
    );

    final result = await api.getRoutePreview(
      fromLat: 42.98,
      fromLng: 47.50,
      toLat: 42.99,
      toLng: 47.51,
    );

    expect(client.lastPath, startsWith('/api/v1/routing/preview?'));
    expect(client.lastHeaders?['Authorization'], 'Bearer access-token');
    expect(result?.points, hasLength(2));
    expect(result?.distanceMeters, 1200);
    expect(result?.durationSeconds, 300);
  });
}
