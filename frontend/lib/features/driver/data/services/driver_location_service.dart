import 'dart:async';

import 'package:geolocator/geolocator.dart';

class DriverLocationService {
  StreamSubscription<Position>? _positionSubscription;

  Future<bool> checkPermissions() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const DriverLocationException(
        'Р’РєР»СЋС‡РёС‚Рµ РіРµРѕР»РѕРєР°С†РёСЋ РґР»СЏ РїРѕРёСЃРєР° Р·Р°РєР°Р·РѕРІ.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const DriverLocationException(
        'РќРµС‚ РґРѕСЃС‚СѓРїР° Рє РіРµРѕР»РѕРєР°С†РёРё. Р Р°Р·СЂРµС€РёС‚Рµ GPS РґР»СЏ СЂР°Р±РѕС‚С‹ РІРѕРґРёС‚РµР»СЏ.',
      );
    }

    return true;
  }

  Future<Position> getCurrentPosition() async {
    await checkPermissions();
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );
  }

  Future<void> startLocationTracking({
    required String driverId,
    Duration interval = const Duration(seconds: 10),
    void Function(Position position)? onPosition,
  }) async {
    await stopLocationTracking();
    await checkPermissions();

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        timeLimit: interval * 2,
      ),
    ).listen(onPosition);
  }

  Future<void> stopLocationTracking() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  Future<void> dispose() async {
    await stopLocationTracking();
  }
}

class DriverLocationException implements Exception {
  const DriverLocationException(this.message);

  final String message;

  @override
  String toString() => message;
}
