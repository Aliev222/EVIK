import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await PushNotificationService.instance.showBackgroundNotification(message);
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
    'evik_fcm_high_importance',
    'Авро уведомления',
    description: 'Order, payment, and driver status alerts',
    importance: Importance.high,
  );

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  void Function(String route)? _routeHandler;
  String? Function()? _currentRouteResolver;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      await _requestPermission();
      await _initializeLocalNotifications();
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: false,
        badge: true,
        sound: true,
      );

      _foregroundSubscription =
          FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      _openedSubscription =
          FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      final initialMessage =
          await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        scheduleMicrotask(() => _handleNotificationTap(initialMessage));
      }
    } catch (_) {
      // Firebase not available (web or unsupported platform)
    }

    _initialized = true;
  }

  void setRouteHandler(void Function(String route) handler) {
    _routeHandler = handler;
  }

  void setCurrentRouteResolver(String? Function() resolver) {
    _currentRouteResolver = resolver;
  }

  Future<String?> getToken() async {
    try { return await FirebaseMessaging.instance.getToken(); } catch (_) { return null; }
  }

  Stream<String> get onTokenRefresh {
    try { return FirebaseMessaging.instance.onTokenRefresh; } catch (_) { return const Stream.empty(); }
  }

  Future<void> showBackgroundNotification(RemoteMessage message) async {
    await _initializeLocalNotifications();
    await _showSystemNotification(message);
  }

  Future<void> dispose() async {
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
  }

  Future<void> _requestPermission() async {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
  }

  Future<void> _initializeLocalNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();

    await _localNotifications.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (response) {
        final route = _routeFromPayload(response.payload);
        if (route != null) {
          _routeHandler?.call(route);
        }
      },
    );

    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_androidChannel);
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final title = _notificationTitle(message);
    final body = _notificationBody(message);
    final route = routeForMessage(message);
    final messenger = rootScaffoldMessengerKey.currentState;

    if (messenger == null) {
      debugPrint('FCM foreground message without messenger: ${message.data}');
      return;
    }

    if (route != null) {
      final currentRoute = _currentRouteResolver?.call();
      if (currentRoute != null && currentRoute == route) {
        return;
      }
    }

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            body.isEmpty ? title : '$title\n$body',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(left: 16, right: 16, bottom: 80),
          duration: const Duration(seconds: 6),
          action: route == null
              ? null
              : SnackBarAction(
                  label: 'Open',
                  onPressed: () => _routeHandler?.call(route),
                ),
        ),
      );
  }

  Future<void> _showSystemNotification(RemoteMessage message) async {
    final title = _notificationTitle(message);
    final body = _notificationBody(message);
    if (title.isEmpty && body.isEmpty) return;

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'evik_fcm_high_importance',
        'Авро уведомления',
        channelDescription: 'Order, payment, and driver status alerts',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _localNotifications.show(
      id: message.messageId.hashCode,
      title: title,
      body: body,
      notificationDetails: details,
      payload: jsonEncode(message.data),
    );
  }

  void _handleNotificationTap(RemoteMessage message) {
    final route = routeForMessage(message);
    if (route != null) {
      _routeHandler?.call(route);
    }
  }

  String? routeForMessage(RemoteMessage message) {
    return _routeFromData(message.data);
  }

  String? _routeFromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        return _routeFromData(decoded);
      }
    } catch (_) {
      return payload.startsWith('/') ? payload : null;
    }
    return null;
  }

  String? _routeFromData(Map<String, dynamic> data) {
    final type = data['type']?.toString();
    final route = data['route']?.toString();
    if (route != null && route.startsWith('/')) {
      return route;
    }

    return switch (type) {
      'new_order_nearby' => '/',
      'client_cancelled_order' => '/',
      'payout_approved' || 'payout_rejected' => '/',
      'driver_accepted_order' => '/order/driver-info',
      'driver_on_way' || 'driver_arrived' => '/order/tracking',
      'order_completed' => '/order/completion',
      'payment_succeeded' => '/order/completion',
      'payment_failed' => '/order/tracking',
      _ => null,
    };
  }

  String _notificationTitle(RemoteMessage message) {
    return message.notification?.title ??
        message.data['title']?.toString() ??
        'Авро';
  }

  String _notificationBody(RemoteMessage message) {
    return message.notification?.body ??
        message.data['body']?.toString() ??
        message.data['message']?.toString() ??
        '';
  }
}
