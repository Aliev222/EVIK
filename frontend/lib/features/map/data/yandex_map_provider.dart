import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/map/map_provider.dart';

class YandexMapProvider implements MapProvider {
  YandexMapProvider();

  static const MethodChannel _bootstrapChannel = MethodChannel('evik/yandex_map_provider');

  final StreamController<Location> _locationController = StreamController<Location>.broadcast();

  int? _mapId;
  bool _available = false;

  bool get isAvailable => _available;

  void attachMap(int mapId) {
    _mapId = mapId;
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
        debugPrint('YandexMapProvider: MapKit unavailable, fallback will be used.');
      }
    } catch (e) {
      _available = false;
      debugPrint('YandexMapProvider init failed: $e');
    }
  }

  @override
  Future<void> moveCamera(double lat, double lng) async {
    if (!_available || _mapId == null) return;
    final channel = MethodChannel('evik/yandex_map_$_mapId');
    try {
      await channel.invokeMethod<void>('moveCamera', <String, dynamic>{
        'lat': lat,
        'lng': lng,
        'zoom': 15.0,
      });
    } catch (e) {
      debugPrint('YandexMapProvider moveCamera failed: $e');
    }
  }

  @override
  Stream<Location> onLocationChanged() {
    // TODO: Wire real location stream (FusedLocationProvider + runtime permissions).
    return _locationController.stream;
  }
}
