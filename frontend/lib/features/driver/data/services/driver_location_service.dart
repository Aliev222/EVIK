import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'package:tow_truck_frontend/core/services/location_service.dart';

class DriverLocationService {
  StreamSubscription<Position>? _positionSubscription;

  Future<bool> checkPermissions({bool requireBackground = false}) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const DriverLocationException(
        'Включите геолокацию для поиска заказов.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const DriverLocationException(
        'Нет доступа к геолокации. Разрешите GPS для работы водителя.',
      );
    }

    if (requireBackground && !kIsWeb) {
      if (defaultTargetPlatform == TargetPlatform.android &&
          permission == LocationPermission.whileInUse) {
        // Android requests background access separately after foreground
        // permission has already been granted.
        permission = await Geolocator.requestPermission();
      }
      if ((defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS) &&
          permission != LocationPermission.always) {
        throw const DriverLocationException(
          'Для работы на линии разрешите геолокацию «Всегда» в настройках приложения.',
        );
      }
    }

    return true;
  }

  Future<Position> getCurrentPosition() async {
    await checkPermissions();
    return LocationService.getCurrentPositionWithFallback();
  }

  Future<void> startLocationTracking({
    required String driverId,
    Duration interval = const Duration(seconds: 10),
    void Function(Position position)? onPosition,
    void Function(Object error)? onError,
  }) async {
    await stopLocationTracking();
    await checkPermissions(requireBackground: true);

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: driverLocationSettingsForPlatform(
        defaultTargetPlatform,
        interval: interval,
      ),
    ).listen(onPosition, onError: onError);
  }

  Future<void> stopLocationTracking() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  Future<void> dispose() async {
    await stopLocationTracking();
  }
}

/// Platform-specific settings for a driver's active shift. Deliberately has
/// no [LocationSettings.timeLimit]: a timeout terminates the position stream
/// when a stationary vehicle emits no update.
LocationSettings driverLocationSettingsForPlatform(
  TargetPlatform platform, {
  required Duration interval,
}) {
  switch (platform) {
    case TargetPlatform.android:
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        intervalDuration: interval,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Авро — водитель на линии',
          notificationText: 'Геолокация используется для получения заказов',
          notificationChannelName: 'Работа водителя',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    case TargetPlatform.iOS:
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        activityType: ActivityType.automotiveNavigation,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
    case TargetPlatform.linux:
    case TargetPlatform.fuchsia:
      return const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      );
  }
}

class DriverLocationException implements Exception {
  const DriverLocationException(this.message);

  final String message;

  @override
  String toString() => message;
}
