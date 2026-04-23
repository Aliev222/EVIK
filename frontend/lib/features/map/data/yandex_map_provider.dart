import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/map/map_provider.dart';

class YandexMapProvider implements MapProvider {
  YandexMapProvider();

  static const MethodChannel _bootstrapChannel =
      MethodChannel('evik/yandex_map_provider');

  final StreamController<Location> _locationController =
      StreamController<Location>.broadcast();
  final StreamController<RouteSummary?> _routeSummaryController =
      StreamController<RouteSummary?>.broadcast();
  StreamSubscription<Position>? _positionSubscription;

  int? _mapId;
  bool _available = false;
  List<MapMarker> _currentMarkers = const <MapMarker>[];
  List<Location> _currentRoute = const <Location>[];

  bool get isAvailable => _available;

  void attachMap(int mapId) {
    _mapId = mapId;
    _mapChannel.setMethodCallHandler(_handleMapCallback);
    unawaited(_syncMapState());
  }

  @override
  Future<void> init() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      _available = false;
      return;
    }

    try {
      final ready = await _bootstrapChannel.invokeMethod<bool>('isAvailable');
      _available = ready ?? false;
      if (!_available) {
        debugPrint(
            'YandexMapProvider: MapKit unavailable, fallback will be used.');
      }
    } catch (e) {
      _available = false;
      debugPrint('YandexMapProvider init failed: $e');
    }

    await _startLocationTracking();
  }

  @override
  Future<void> moveCamera(double lat, double lng) async {
    if (!_available || _mapId == null) return;
    try {
      await _mapChannel.invokeMethod<void>('moveCamera', <String, dynamic>{
        'lat': lat,
        'lng': lng,
        'zoom': 15.0,
      });
    } catch (e) {
      debugPrint('YandexMapProvider moveCamera failed: $e');
    }
  }

  @override
  Future<void> setMarkers(List<MapMarker> markers) async {
    _currentMarkers = List<MapMarker>.unmodifiable(markers);
    if (!_available || _mapId == null) return;
    try {
      await _mapChannel.invokeMethod<void>('setMarkers', <String, dynamic>{
        'markers': _currentMarkers
            .map(
              (marker) => <String, dynamic>{
                'id': marker.id,
                'lat': marker.location.lat,
                'lng': marker.location.lng,
                if (marker.title != null) 'title': marker.title,
              },
            )
            .toList(growable: false),
      });
    } catch (e) {
      debugPrint('YandexMapProvider setMarkers failed: $e');
    }
  }

  @override
  Future<void> clearMarkers() async {
    _currentMarkers = const <MapMarker>[];
    if (!_available || _mapId == null) return;
    try {
      await _mapChannel.invokeMethod<void>('clearMarkers');
    } catch (e) {
      debugPrint('YandexMapProvider clearMarkers failed: $e');
    }
  }

  @override
  Future<void> setRoute(List<Location> points) async {
    _currentRoute = List<Location>.unmodifiable(points);
    if (!_available || _mapId == null) return;
    try {
      await _mapChannel.invokeMethod<void>('setRoute', <String, dynamic>{
        'points': _currentRoute
            .map(
              (point) => <String, dynamic>{
                'lat': point.lat,
                'lng': point.lng,
              },
            )
            .toList(growable: false),
      });
    } catch (e) {
      debugPrint('YandexMapProvider setRoute failed: $e');
      _routeSummaryController.add(null);
    }
  }

  @override
  Future<void> clearRoute() async {
    _currentRoute = const <Location>[];
    _routeSummaryController.add(null);
    if (!_available || _mapId == null) return;
    try {
      await _mapChannel.invokeMethod<void>('clearRoute');
    } catch (e) {
      debugPrint('YandexMapProvider clearRoute failed: $e');
    }
  }

  @override
  Stream<Location> onLocationChanged() {
    return _locationController.stream;
  }

  @override
  Stream<RouteSummary?> onRouteSummaryChanged() {
    return _routeSummaryController.stream;
  }

  MethodChannel get _mapChannel => MethodChannel('evik/yandex_map_$_mapId');

  Future<void> _syncMapState() async {
    if (!_available || _mapId == null) return;
    if (_currentMarkers.isEmpty) {
      await clearMarkers();
    } else {
      await setMarkers(_currentMarkers);
    }
    if (_currentRoute.isEmpty) {
      await clearRoute();
    } else {
      await setRoute(_currentRoute);
    }
  }

  Future<void> _handleMapCallback(MethodCall call) async {
    switch (call.method) {
      case 'onRouteSummary':
        final payload = call.arguments;
        if (payload is! Map) {
          _routeSummaryController.add(null);
          return;
        }
        final distanceMeters =
            (payload['distance_meters'] as num?)?.toDouble() ?? 0;
        final durationSeconds =
            (payload['duration_seconds'] as num?)?.toDouble() ?? 0;
        if (distanceMeters <= 0 || durationSeconds <= 0) {
          _routeSummaryController.add(null);
          return;
        }
        _routeSummaryController.add(
          RouteSummary(
            distanceKm: distanceMeters / 1000,
            etaMinutes: math.max(1, (durationSeconds / 60).round()),
          ),
        );
        return;
      default:
        return;
    }
  }

  Future<void> _startLocationTracking() async {
    if (_positionSubscription != null) return;

    final granted = await _ensureLocationPermission();
    if (!granted) return;

    final settings = switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 5,
          intervalDuration: const Duration(seconds: 2),
        ),
      _ => const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
    };

    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: settings).listen(
      (position) {
        _locationController.add(
          Location(lat: position.latitude, lng: position.longitude),
        );
      },
      onError: (Object e, StackTrace _) {
        debugPrint('YandexMapProvider location stream failed: $e');
      },
    );
  }

  Future<bool> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }
}
