import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:vibration/vibration.dart';

import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';

enum DriverHapticType {
  light,
  success,
  warning,
}

/// Asset-пути к звуковым файлам (см. assets/audio/).
class SoundAsset {
  SoundAsset._();

  static const String shiftStarted = 'assets/audio/начало работы.mp3';
  static const String tripStarted = 'assets/audio/начало движения.mp3';
  static const String paymentChangedToCash = 'assets/audio/оплатаналичные.mp3';
  static const String paymentChangedToCard = 'assets/audio/оплатакартой.mp3';
  static const String longShift = 'assets/audio/долгонасмене.mp3';
  static const String orderCancelled = 'assets/audio/заказ отменен.mp3';
  static const String driverArrived = 'assets/audio/сигналводителя.mp3';
}

abstract class DriverNotificationService {
  Future<void> playAsset(String assetPath);
  Future<void> playShiftStarted();
  Future<void> playTripStarted();
  Future<void> playPaymentChanged({required bool isCash});
  Future<void> playLongShift();
  Future<void> playOrderCancelled();
  Future<void> playDriverArrived();
  Future<void> ensureInitialized();
  Future<void> playNewOrderSound();
  Future<void> showOrderNotification(Order order);
  Future<void> scheduleLocationReminder();
  Future<void> vibrateFeedback(DriverHapticType type);
  Future<void> dispose();
}

final driverNotificationServiceProvider =
    Provider<DriverNotificationService>((ref) {
  final service = AudioDriverNotificationService();
  ref.onDispose(service.dispose);
  return service;
});

class AudioDriverNotificationService implements DriverNotificationService {
  AudioDriverNotificationService()
      : _notifications = FlutterLocalNotificationsPlugin(),
        _player = AudioPlayer();

  final FlutterLocalNotificationsPlugin _notifications;
  final AudioPlayer _player;
  bool _initialized = false;

  /// Проигрывает произвольный аудио-asset через just_audio.
  Future<void> playAsset(String assetPath) async {
    try {
      await _player.stop();
      await _player.setAsset(assetPath);
      await _player.play();
    } catch (_) {
      // Звук не критичен — молча пропускаем ошибки воспроизведения.
    }
  }

  /// Водитель вышел на смену.
  Future<void> playShiftStarted() => playAsset(SoundAsset.shiftStarted);

  /// Водитель забрал клиента и повёз машину.
  Future<void> playTripStarted() => playAsset(SoundAsset.tripStarted);

  /// Метод оплаты сменён во время поездки.
  Future<void> playPaymentChanged({required bool isCash}) => playAsset(isCash
      ? SoundAsset.paymentChangedToCash
      : SoundAsset.paymentChangedToCard);

  /// Водитель слишком долго на смене.
  Future<void> playLongShift() => playAsset(SoundAsset.longShift);

  /// Заказ отменён другой стороной.
  Future<void> playOrderCancelled() => playAsset(SoundAsset.orderCancelled);

  /// Водитель приехал к клиенту (звук у клиента).
  Future<void> playDriverArrived() => playAsset(SoundAsset.driverArrived);

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
    if (kIsWeb) return;
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
