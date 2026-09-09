import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:tow_truck_frontend/features/driver/data/services/driver_location_service.dart';

void main() {
  test('Android shift tracking is continuous and uses a foreground service',
      () {
    final settings = driverLocationSettingsForPlatform(
      TargetPlatform.android,
      interval: const Duration(seconds: 10),
    );

    expect(settings, isA<AndroidSettings>());
    final android = settings as AndroidSettings;
    expect(android.timeLimit, isNull);
    expect(android.intervalDuration, const Duration(seconds: 10));
    expect(android.foregroundNotificationConfig, isNotNull);
    expect(android.foregroundNotificationConfig!.setOngoing, isTrue);
  });

  test('iOS shift tracking enables automotive background updates', () {
    final settings = driverLocationSettingsForPlatform(
      TargetPlatform.iOS,
      interval: const Duration(seconds: 10),
    );

    expect(settings, isA<AppleSettings>());
    final apple = settings as AppleSettings;
    expect(apple.timeLimit, isNull);
    expect(apple.activityType, ActivityType.automotiveNavigation);
    expect(apple.pauseLocationUpdatesAutomatically, isFalse);
    expect(apple.allowBackgroundLocationUpdates, isTrue);
    expect(apple.showBackgroundLocationIndicator, isTrue);
  });
}
