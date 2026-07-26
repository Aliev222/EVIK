import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
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
    final permission = await _ensureLocationPermission();
    if (!permission) {
      throw const LocationException('Доступ к геолокации не разрешен');
    }

    final position = await getCurrentPositionWithFallback();
    final isMocked = position.isMocked;

    final address = await _getAddressByCoordinates(
      position.latitude,
      position.longitude,
    );

    return LocationModel(
      lat: position.latitude,
      lng: position.longitude,
      address: address ??
          _coordinatesAddress(position.latitude, position.longitude),
      isMocked: isMocked,
    );
  }

  static Future<Position> getCurrentPositionWithFallback() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (_) {
      // fallback to medium accuracy (Wi-Fi + towers)
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5),
        ),
      );
    } catch (_) {
      // fallback to last known position
    }

    final lastKnown = await Geolocator.getLastKnownPosition();
    if (lastKnown != null) {
      return lastKnown;
    }

    throw const LocationException('Не удалось определить местоположение');
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

  static Future<PermissionResult> requestLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return PermissionResult.serviceDisabled;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      return PermissionResult.deniedForever;
    }

    if (permission == LocationPermission.denied) {
      return PermissionResult.denied;
    }

    return PermissionResult.granted;
  }

  Future<bool> _ensureLocationPermission() async {
    final result = await requestLocationPermission();
    return result == PermissionResult.granted;
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
    return '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
  }
}

enum PermissionResult {
  granted,
  denied,
  deniedForever,
  serviceDisabled,
}

class LocationException implements Exception {
  const LocationException(this.message);

  final String message;

  @override
  String toString() => 'LocationException: $message';
}
