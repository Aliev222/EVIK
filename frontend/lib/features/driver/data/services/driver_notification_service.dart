import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:just_audio/just_audio.dart';
import 'package:vibration/vibration.dart';

import '../../../order/domain/entities/order.dart';

enum DriverHapticType {
  light,
  success,
  warning,
}

class DriverNotificationService {
  DriverNotificationService()
      : _notifications = FlutterLocalNotificationsPlugin(),
        _player = AudioPlayer();

  final FlutterLocalNotificationsPlugin _notifications;
  final AudioPlayer _player;
  bool _initialized = false;

  Future<void> ensureInitialized() async {
    if (_initialized) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _notifications.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
    );
    _initialized = true;
  }

  Future<void> playNewOrderSound() async {
    await ensureInitialized();
    try {
      await _player.stop();
      SystemSound.play(SystemSoundType.alert);
    } catch (_) {
      SystemSound.play(SystemSoundType.alert);
    }
  }

  Future<void> showOrderNotification(Order order) async {
    await ensureInitialized();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'driver_orders',
        'Заказы водителя',
        channelDescription: 'Новые заказы и критичные события',
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _notifications.show(
      id: order.id.hashCode,
      title: 'Новый заказ',
      body:
          '${order.pickupLocation.address} -> ${order.dropoffLocation.address}',
      notificationDetails: details,
      payload: order.id,
    );
  }

  Future<void> scheduleLocationReminder() async {
    await ensureInitialized();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'driver_location',
        'Напоминания о локации',
        channelDescription: 'Сервисные уведомления для работы в фоне',
      ),
      iOS: DarwinNotificationDetails(),
    );

    await _notifications.show(
      id: 9001,
      title: 'Проверьте геолокацию',
      body: 'Если заказы не приходят, убедитесь, что GPS и интернет активны.',
      notificationDetails: details,
    );
  }

  Future<void> vibrateFeedback(DriverHapticType type) async {
    final hasVibrator = await Vibration.hasVibrator();
    if (!hasVibrator) {
      return;
    }

    switch (type) {
      case DriverHapticType.light:
        await Vibration.vibrate(duration: 60, amplitude: 80);
        break;
      case DriverHapticType.success:
        await Vibration.vibrate(pattern: <int>[0, 80, 60, 120]);
        break;
      case DriverHapticType.warning:
        await Vibration.vibrate(pattern: <int>[0, 160, 80, 200]);
        break;
    }
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}
