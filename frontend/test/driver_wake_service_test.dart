import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tow_truck_frontend/core/notifications/push_notification_service.dart';
import 'package:tow_truck_frontend/features/driver/data/services/driver_wake_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('driver online intent survives an application restart', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final wakeService = container.read(driverWakeServiceProvider);

    expect(await wakeService.wasOnline(), isFalse);

    await wakeService.markOnline();
    expect(await wakeService.wasOnline(), isTrue);

    await wakeService.markOffline();
    expect(await wakeService.wasOnline(), isFalse);
  });

  test('driver wake notification exposes callback and driver route', () {
    final pushService = PushNotificationService.instance;
    var wakeCalls = 0;

    pushService.onDriverWake = () => wakeCalls++;

    expect(
      pushService.routeForMessage(
        const RemoteMessage(data: <String, dynamic>{'type': 'driver_wake'}),
      ),
      '/driver',
    );
    expect(wakeCalls, 0);

    pushService.onDriverWake = null;
  });
}
