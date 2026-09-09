import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'package:tow_truck_frontend/core/network/api_client.dart';
import 'package:tow_truck_frontend/core/network/api_client_stub.dart'
    if (dart.library.io) '../network/api_client_io.dart' as platform_api;
import 'package:tow_truck_frontend/core/network/auth_retry_coordinator.dart';

/// Backend-owned map operations used by the mobile app.
///
/// The backend is the only component that talks to Nominatim/OSRM. This keeps
/// provider policies, rate limits and the future Russian-host migration out of
/// published mobile binaries.
class MapApi {
  MapApi({
    ApiClient? apiClient,
    String? Function()? accessTokenProvider,
  })  : _apiClient = apiClient ?? platform_api.createPlatformApiClient(),
        _accessTokenProvider =
            accessTokenProvider ?? AuthRetryCoordinator.accessToken;

  final ApiClient _apiClient;
  final String? Function()? _accessTokenProvider;

  Future<OsmLocation?> geocode(String address) async {
    final query = address.trim();
    if (query.length < 3) return null;

    final path = Uri(
      path: '/api/v1/geocode/search',
      queryParameters: <String, String>{'q': query, 'limit': '1'},
    ).toString();

    try {
      final response = await _apiClient.get(path);
      final results = response['results'];
      if (results is! List || results.isEmpty || results.first is! Map) {
        return null;
      }
      final first = Map<String, dynamic>.from(results.first as Map);
      final lat = _asDouble(first['lat']);
      final lng = _asDouble(first['lng']);
      if (lat == null || lng == null) return null;

      return OsmLocation(
        latitude: lat,
        longitude: lng,
        address: first['display_name']?.toString() ?? query,
      );
    } catch (error) {
      debugPrint('MapApi geocoding error: $error');
      return null;
    }
  }

  Future<String?> reverseGeocode({
    required double lat,
    required double lng,
  }) async {
    final path = Uri(
      path: '/api/v1/geocode/reverse',
      queryParameters: <String, String>{
        'lat': lat.toStringAsFixed(6),
        'lng': lng.toStringAsFixed(6),
      },
    ).toString();

    try {
      final response = await _apiClient.get(path);
      final address = response['address']?.toString().trim();
      return address == null || address.isEmpty ? null : address;
    } catch (error) {
      debugPrint('MapApi reverse geocoding error: $error');
      return null;
    }
  }

  Future<RoutePreview?> getRoutePreview({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) async {
    final path = Uri(
      path: '/api/v1/routing/preview',
      queryParameters: <String, String>{
        'fromLat': fromLat.toString(),
        'fromLng': fromLng.toString(),
        'toLat': toLat.toString(),
        'toLng': toLng.toString(),
      },
    ).toString();

    try {
      final response = await _apiClient.get(path, headers: _authHeaders());
      final rawPoints = response['points'];
      final points = rawPoints is List
          ? rawPoints
              .whereType<Map>()
              .map(Map<String, dynamic>.from)
              .map((point) {
                final lat = _asDouble(point['lat']);
                final lng = _asDouble(point['lng']);
                return lat == null || lng == null ? null : LatLng(lat, lng);
              })
              .whereType<LatLng>()
              .toList(growable: false)
          : const <LatLng>[];

      return RoutePreview(
        points: points.isEmpty
            ? <LatLng>[LatLng(fromLat, fromLng), LatLng(toLat, toLng)]
            : points,
        distanceMeters: _asDouble(
              response['distanceMeters'] ?? response['distance_meters'],
            ) ??
            0,
        durationSeconds: _asDouble(
              response['durationSeconds'] ?? response['duration_seconds'],
            ) ??
            0,
      );
    } catch (error) {
      debugPrint('MapApi route preview error: $error');
      return null;
    }
  }

  Map<String, String>? _authHeaders() {
    final token = _accessTokenProvider?.call();
    if (token == null || token.isEmpty) return null;
    return <String, String>{'Authorization': 'Bearer $token'};
  }

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}

class RoutePreview {
  const RoutePreview({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;

  double get distanceKm => distanceMeters / 1000;
  double get durationMinutes => durationSeconds / 60;
}

class OsmLocation {
  const OsmLocation({
    required this.latitude,
    required this.longitude,
    required this.address,
  });

  final double latitude;
  final double longitude;
  final String address;
}

class OsmPlace {
  const OsmPlace({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.category,
  });

  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final String category;
}
