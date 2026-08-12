import 'package:flutter/foundation.dart';

import 'package:tow_truck_frontend/core/network/api_client_stub.dart'
    if (dart.library.io) '../network/api_client_io.dart'
    as platform_api;
import 'package:tow_truck_frontend/core/network/auth_retry_coordinator.dart';

/// Address resolution client for the Авро backend.
///
/// Reverse geocoding for critical flows (the client home screen address card)
/// must go through the backend endpoint `GET /api/v1/geocode/reverse`, never
/// direct to public OSM/Nominatim — the backend owns the Nominatim User-Agent
/// and the 1 req/s usage policy.
class GeocodingApi {
  GeocodingApi({String? Function()? accessTokenProvider})
      : _accessTokenProvider = accessTokenProvider ?? AuthRetryCoordinator.accessToken;

  final String? Function()? _accessTokenProvider;

  Future<String?> reverseGeocode({
    required double lat,
    required double lng,
  }) async {
    Map<String, String>? headers;
    final token = _accessTokenProvider?.call();
    if (token != null && token.isNotEmpty) {
      headers = <String, String>{'Authorization': 'Bearer $token'};
    }

    final path =
        '/api/v1/geocode/reverse?lat=${lat.toStringAsFixed(6)}&lng=${lng.toStringAsFixed(6)}';

    try {
      final api = platform_api.createPlatformApiClient();
      final response = await api.get(path, headers: headers);
      final address = response['address']?.toString();
      if (address == null || address.trim().isEmpty) {
        return null;
      }
      return address;
    } catch (e) {
      debugPrint('GeocodingApi reverse error: $e');
      return null;
    }
  }
}