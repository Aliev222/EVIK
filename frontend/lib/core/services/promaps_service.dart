import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../constants/app_constants.dart';

/// ProMaps API service for maps and routing
/// Documentation: https://promaps.online/
class ProMapsService {
  static const String _baseUrl = 'https://api.promaps.online';

  // API ключи из AppConstants
  static const String _mapsApiKey = AppConstants.promapsMapsApiKey;
  static const String _roadApiKey = AppConstants.promapsRoadApiKey;
  static const String _sdkApiKey = AppConstants.promapsSdkApiKey;

  /// Получить тайлы карты для отображения
  static String getMapTileUrl({
    required int zoom,
    required int x,
    required int y,
    String style = 'default',
  }) {
    return '$_baseUrl/tiles/$style/$zoom/$x/$y.png?key=$_mapsApiKey';
  }

  /// Получить URL для встраиваемой карты
  static String getEmbedMapUrl({
    required double lat,
    required double lng,
    int zoom = 14,
    String style = 'default',
  }) {
    return '$_baseUrl/embed?lat=$lat&lng=$lng&zoom=$zoom&style=$style&key=$_sdkApiKey';
  }

  /// Геокодирование - получить координаты по адресу
  static Future<ProMapsLocation?> geocode(String address) async {
    try {
      final response = await http.get(
        Uri.parse(
          '$_baseUrl/geocoding/search?q=${Uri.encodeQueryComponent(address)}',
        ),
        headers: {
          'Authorization': 'Bearer $_mapsApiKey',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['results'] != null && data['results'].isNotEmpty) {
          final result = data['results'][0];
          return ProMapsLocation(
            latitude: result['lat'].toDouble(),
            longitude: result['lng'].toDouble(),
            address: result['formatted_address'] ?? address,
          );
        }
      }
    } catch (e) {
      debugPrint('ProMaps geocoding error: $e');
    }
    return null;
  }

  static Future<ProMapsLocation?> searchLocation(String query) {
    return geocode(query);
  }

  static Future<ProMapsLocation?> getCurrentLocation() async {
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

    return ProMapsLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      address: address ?? 'Current location',
    );
  }

  /// Обратное геокодирование - получить адрес по координатам
  static Future<String?> reverseGeocode({
    required double lat,
    required double lng,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/geocoding/reverse?lat=$lat&lng=$lng'),
        headers: {
          'Authorization': 'Bearer $_mapsApiKey',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['formatted_address'] as String?;
      }
    } catch (e) {
      debugPrint('ProMaps reverse geocoding error: $e');
    }
    return null;
  }

  /// Построение маршрута между двумя точками
  static Future<ProMapsRoute?> getRoute({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
    String profile = 'driving', // driving, walking, cycling
  }) async {
    try {
      final response = await http.get(
        Uri.parse(
          '$_baseUrl/routing/route?'
          'start=$fromLng,$fromLat&'
          'end=$toLng,$toLat&'
          'profile=$profile',
        ),
        headers: {
          'Authorization': 'Bearer $_roadApiKey',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          return ProMapsRoute(
            distance: route['distance']?.toDouble() ?? 0.0,
            duration: route['duration']?.toDouble() ?? 0.0,
            polyline: route['geometry'] as String?,
            steps: (route['legs']?[0]?['steps'] as List?)
                ?.map((step) => ProMapsRouteStep(
                      instruction: step['maneuver']?['instruction'] ?? '',
                      distance: step['distance']?.toDouble() ?? 0.0,
                      duration: step['duration']?.toDouble() ?? 0.0,
                    ))
                .toList(),
          );
        }
      }
    } catch (e) {
      debugPrint('ProMaps routing error: $e');
    }
    return null;
  }

  /// Поиск мест поблизости
  static Future<List<ProMapsPlace>> searchNearby({
    required double lat,
    required double lng,
    required String query,
    double radius = 1000, // метров
    int limit = 10,
  }) async {
    try {
      final response = await http.get(
        Uri.parse(
          '$_baseUrl/places/search?'
          'lat=$lat&lng=$lng&'
          'q=${Uri.encodeComponent(query)}&'
          'radius=$radius&'
          'limit=$limit',
        ),
        headers: {
          'Authorization': 'Bearer $_mapsApiKey',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['results'] != null) {
          return (data['results'] as List)
              .map((place) => ProMapsPlace(
                    name: place['name'] ?? '',
                    address: place['formatted_address'] ?? '',
                    latitude: place['lat']?.toDouble() ?? 0.0,
                    longitude: place['lng']?.toDouble() ?? 0.0,
                    category: place['category'] ?? '',
                  ))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('ProMaps search error: $e');
    }
    return [];
  }
}

/// Местоположение с координатами и адресом
class ProMapsLocation {
  final double latitude;
  final double longitude;
  final String address;

  const ProMapsLocation({
    required this.latitude,
    required this.longitude,
    required this.address,
  });
}

/// Маршрут с геометрией и информацией
class ProMapsRoute {
  final double distance; // метры
  final double duration; // секунды
  final String? polyline; // encoded polyline
  final List<ProMapsRouteStep>? steps;

  const ProMapsRoute({
    required this.distance,
    required this.duration,
    this.polyline,
    this.steps,
  });

  /// Расстояние в километрах
  double get distanceKm => distance / 1000;

  /// Время в минутах
  double get durationMinutes => duration / 60;
}

/// Шаг маршрута
class ProMapsRouteStep {
  final String instruction;
  final double distance;
  final double duration;

  const ProMapsRouteStep({
    required this.instruction,
    required this.distance,
    required this.duration,
  });
}

/// Место/POI
class ProMapsPlace {
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final String category;

  const ProMapsPlace({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.category,
  });
}
