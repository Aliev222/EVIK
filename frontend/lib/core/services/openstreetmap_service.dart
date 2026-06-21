import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'package:tow_truck_frontend/core/constants/app_constants.dart';

class OpenStreetMapService {
  static const String _userAgent = 'Avro mobile app';

  static String getMapTileUrl({
    required int zoom,
    required int x,
    required int y,
  }) {
    return AppConstants.openStreetMapTileUrl
        .replaceAll('{z}', zoom.toString())
        .replaceAll('{x}', x.toString())
        .replaceAll('{y}', y.toString());
  }

  static Future<OsmLocation?> geocode(String address) async {
    final query = address.trim();
    if (query.isEmpty) return null;

    try {
      final uri = Uri.parse(AppConstants.nominatimBaseUrl).replace(
        path: '/search',
        queryParameters: <String, String>{
          'q': query,
          'format': 'jsonv2',
          'limit': '1',
          'addressdetails': '1',
        },
      );
      final response = await http.get(uri, headers: _headers).timeout(
            const Duration(seconds: 10),
          );

      if (response.statusCode != 200) return null;
      final results = jsonDecode(response.body) as List<dynamic>;
      if (results.isEmpty) return null;

      final result = results.first as Map<String, dynamic>;
      final lat = double.tryParse(result['lat']?.toString() ?? '');
      final lng = double.tryParse(result['lon']?.toString() ?? '');
      if (lat == null || lng == null) return null;

      return OsmLocation(
        latitude: lat,
        longitude: lng,
        address: result['display_name']?.toString() ?? query,
      );
    } catch (e) {
      debugPrint('OSM geocoding error: $e');
      return null;
    }
  }

  static Future<OsmLocation?> searchLocation(String query) => geocode(query);

  static Future<OsmLocation?> getCurrentLocation() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    ).timeout(const Duration(seconds: 10));

    final address = await reverseGeocode(
      lat: position.latitude,
      lng: position.longitude,
    );

    return OsmLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      address: address ?? 'Current location',
    );
  }

  static Future<String?> reverseGeocode({
    required double lat,
    required double lng,
  }) async {
    try {
      final uri = Uri.parse(AppConstants.nominatimBaseUrl).replace(
        path: '/reverse',
        queryParameters: <String, String>{
          'lat': lat.toStringAsFixed(6),
          'lon': lng.toStringAsFixed(6),
          'format': 'jsonv2',
        },
      );
      final response = await http.get(uri, headers: _headers).timeout(
            const Duration(seconds: 10),
          );

      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['display_name']?.toString();
    } catch (e) {
      debugPrint('OSM reverse geocoding error: $e');
      return null;
    }
  }

  static Future<RoutePreview?> getRoutePreview({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
    String profile = 'driving',
  }) async {
    try {
      final normalizedProfile = switch (profile) {
        'walking' => 'foot',
        'cycling' => 'bike',
        _ => 'car',
      };
      final uri = Uri.parse(AppConstants.osrmBaseUrl).replace(
        path: '/route/v1/$normalizedProfile/$fromLng,$fromLat;$toLng,$toLat',
        queryParameters: const <String, String>{
          'overview': 'full',
          'geometries': 'geojson',
          'steps': 'false',
        },
      );

      final response = await http.get(uri, headers: _headers).timeout(
            const Duration(seconds: 15),
          );
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) return null;

      final route = routes.first as Map<String, dynamic>;
      final geometry = route['geometry'] as Map<String, dynamic>?;
      final coordinates =
          geometry?['coordinates'] as List<dynamic>? ?? const [];
      final points = coordinates
          .whereType<List<dynamic>>()
          .where((point) => point.length >= 2)
          .map((point) => LatLng(
                (point[1] as num).toDouble(),
                (point[0] as num).toDouble(),
              ))
          .toList(growable: false);

      return RoutePreview(
        points: points.isEmpty
            ? <LatLng>[LatLng(fromLat, fromLng), LatLng(toLat, toLng)]
            : points,
        distanceMeters: (route['distance'] as num?)?.toDouble() ?? 0,
        durationSeconds: (route['duration'] as num?)?.toDouble() ?? 0,
      );
    } catch (e) {
      debugPrint('OSRM route preview error: $e');
      return null;
    }
  }

  static Future<List<OsmPlace>> searchNearby({
    required double lat,
    required double lng,
    required String query,
    double radius = 1000,
    int limit = 10,
  }) async {
    final location = await geocode('$query near $lat,$lng');
    if (location == null) return const <OsmPlace>[];

    return <OsmPlace>[
      OsmPlace(
        name: query,
        address: location.address,
        latitude: location.latitude,
        longitude: location.longitude,
        category: '',
      ),
    ];
  }

  static Map<String, String> get _headers => const <String, String>{
        'User-Agent': _userAgent,
        'Accept': 'application/json',
      };
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
