import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../../features/order/domain/entities/order.dart';
import 'openstreetmap_service.dart';

class LocationService {
  static LocationService? _instance;

  LocationService._();

  static LocationService get instance {
    _instance ??= LocationService._();
    return _instance!;
  }

  factory LocationService() => instance;

  Future<LocationModel?> getCurrentLocation() async {
    try {
      final permission = await _ensureLocationPermission();
      if (!permission) {
        throw const LocationException('Доступ к геолокации не разрешен');
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      final address = await _getAddressByCoordinates(
        position.latitude,
        position.longitude,
      );

      return LocationModel(
        lat: position.latitude,
        lng: position.longitude,
        address: address ??
            _coordinatesAddress(position.latitude, position.longitude),
      );
    } catch (e) {
      throw LocationException('Ошибка получения геолокации: $e');
    }
  }

  Future<LocationModel?> getLocationByAddress(String address) async {
    if (address.trim().isEmpty) return null;

    try {
      final location = await OpenStreetMapService.searchLocation(address);
      if (location != null) {
        return LocationModel(
          lat: location.latitude,
          lng: location.longitude,
          address: location.address,
        );
      }

      // No fallback to mock data - return null if real geocoding failed
      return null;
    } catch (e) {
      throw LocationException('Ошибка геокодирования: $e');
    }
  }

  Future<double?> calculateRouteDistance({
    required LocationModel from,
    required LocationModel to,
  }) async {
    try {
      final route = await OpenStreetMapService.getRoutePreview(
        fromLat: from.lat,
        fromLng: from.lng,
        toLat: to.lat,
        toLng: to.lng,
      );

      if (route != null && route.distanceKm > 0) {
        return route.distanceKm;
      }

      final straightDistance = Geolocator.distanceBetween(
        from.lat,
        from.lng,
        to.lat,
        to.lng,
      );
      return (straightDistance / 1000) * 1.25;
    } catch (e) {
      return null;
    }
  }

  Future<bool> isLocationServiceEnabled() async {
    return Geolocator.isLocationServiceEnabled();
  }

  Stream<Position> getLocationStream() {
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }

  Future<int?> calculateEstimatedTime({
    required LocationModel from,
    required LocationModel to,
  }) async {
    try {
      final route = await OpenStreetMapService.getRoutePreview(
        fromLat: from.lat,
        fromLng: from.lng,
        toLat: to.lat,
        toLng: to.lng,
      );
      if (route != null && route.durationMinutes > 0) {
        return route.durationMinutes.round();
      }

      final distance = await calculateRouteDistance(from: from, to: to);
      if (distance == null) return null;

      final timeInHours = distance / 25;
      return (timeInHours * 60).round();
    } catch (e) {
      return null;
    }
  }

  Future<bool> _ensureLocationPermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return permission != LocationPermission.denied &&
        permission != LocationPermission.deniedForever;
  }

  Future<String?> _getAddressByCoordinates(double lat, double lng) async {
    try {
      return await OpenStreetMapService.reverseGeocode(lat: lat, lng: lng) ??
          _coordinatesAddress(lat, lng);
    } catch (e) {
      return _coordinatesAddress(lat, lng);
    }
  }

  String _coordinatesAddress(double lat, double lng) {
    return 'Москва, ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
  }

  Future<LocationModel?> _mockGeocode(String address) async {
    await Future.delayed(const Duration(milliseconds: 250));

    final normalizedAddress = address.toLowerCase();
    final mockLocations = <String, LocationModel>{
      'москва': const LocationModel(
        lat: 55.7558,
        lng: 37.6173,
        address: 'Москва, Россия',
      ),
      'спб': const LocationModel(
        lat: 59.9311,
        lng: 30.3609,
        address: 'Санкт-Петербург, Россия',
      ),
      'санкт-петербург': const LocationModel(
        lat: 59.9311,
        lng: 30.3609,
        address: 'Санкт-Петербург, Россия',
      ),
      'екатеринбург': const LocationModel(
        lat: 56.8431,
        lng: 60.6454,
        address: 'Екатеринбург, Россия',
      ),
    };

    for (final entry in mockLocations.entries) {
      if (normalizedAddress.contains(entry.key)) {
        return entry.value;
      }
    }

    return LocationModel(
      lat: 55.7558 + ((-1 + 2 * (DateTime.now().millisecond / 1000)) * 0.1),
      lng: 37.6173 + ((-1 + 2 * (DateTime.now().microsecond / 1000000)) * 0.1),
      address: address,
    );
  }
}

class LocationException implements Exception {
  const LocationException(this.message);

  final String message;

  @override
  String toString() => 'LocationException: $message';
}
