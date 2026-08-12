import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'geocoding_api.dart';
import 'openstreetmap_service.dart';

class LocationService {
  static LocationService? _instance;

  LocationService._() : _geocodingApi = GeocodingApi();

  final GeocodingApi _geocodingApi;

  static LocationService get instance {
    _instance ??= LocationService._();
    return _instance!;
  }

  factory LocationService() => instance;

  Future<LocationModel?> getCurrentLocation() async {
    final fix = await getCurrentLocationFix();
    if (fix == null) return null;
    return LocationModel(
      lat: fix.lat,
      lng: fix.lng,
      address: fix.address ?? _coordinatesAddress(fix.lat, fix.lng),
      isMocked: fix.isMocked,
    );
  }

  /// Resolves the current position and its reverse-geocoded address.
  ///
  /// Returns `null` when location access is not permitted. When a real address
  /// could not be reverse-geocoded [GeoFix.address] is `null` (and the caller
  /// should surface an honest "could not determine the address" state instead
  /// of presenting technical coordinates as a real address).
  Future<GeoFix?> getCurrentLocationFix() async {
    final permission = await _ensureLocationPermission();
    if (!permission) {
      throw const LocationException('Доступ к геолокации не разрешен');
    }

    final position = await getCurrentPositionWithFallback();

    String? address;
    try {
      address = await _geocodingApi.reverseGeocode(
        lat: position.latitude,
        lng: position.longitude,
      );
    } catch (_) {
      address = null;
    }

    return GeoFix(
      lat: position.latitude,
      lng: position.longitude,
      address: address,
      isMocked: position.isMocked,
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

  String _coordinatesAddress(double lat, double lng) {
    return '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
  }
}

/// A resolved geographic fix. [address] is `null` when reverse geocoding
/// could not produce a real address, so callers can show an honest
/// "address unknown" state instead of faking one.
class GeoFix {
  const GeoFix({
    required this.lat,
    required this.lng,
    required this.address,
    required this.isMocked,
  });

  final double lat;
  final double lng;
  final String? address;
  final bool isMocked;
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
