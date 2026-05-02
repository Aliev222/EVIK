import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'websocket_client.dart';
import '../../features/order/domain/entities/order.dart';
import '../constants/app_constants.dart';

const defaultWsUrl = String.fromEnvironment(
  'EVIK_WS_URL',
  defaultValue: kDebugMode
    ? 'ws://localhost:8080/ws/orders'      // Development
    : 'wss://tow-truck.onrender.com/ws/orders',      // Production on Render
);

WebSocketClient createPlatformWebSocketClient() {
  if (AppConstants.useMockData) {
    return MockWebSocketClient();
  }
  return IoWebSocketClient();
}

class IoWebSocketClient implements WebSocketClient {
  WebSocketChannel? _channel;
  StreamController<Order>? _orderUpdatesController;
  StreamController<String>? _messagesController;
  String? _currentToken;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;

  @override
  Future<void> connect(String url) async {
    final wsUri = Uri.parse(url);
    _channel = IOWebSocketChannel.connect(wsUri);
    _messagesController ??= StreamController<String>.broadcast();

    _channel!.stream.listen(
      (data) {
        _messagesController?.add(data as String);
      },
      onError: (error) {
        debugPrint('WebSocket error: $error');
      },
      onDone: () {
        debugPrint('WebSocket connection closed');
      },
    );
  }

  @override
  Stream<String> messages() {
    _messagesController ??= StreamController<String>.broadcast();
    return _messagesController!.stream;
  }

  @override
  Future<void> send(String message) async {
    _channel?.sink.add(message);
  }

  @override
  Future<void> disconnect() async {
    _channel?.sink.close();
    _channel = null;
    await _messagesController?.close();
    _messagesController = null;
  }

  Stream<Order> watchOrderUpdates({required String accessToken}) {
    if (_orderUpdatesController != null && _currentToken == accessToken) {
      return _orderUpdatesController!.stream;
    }

    _disconnect();
    _currentToken = accessToken;
    _orderUpdatesController = StreamController<Order>.broadcast();

    _connect(accessToken);

    return _orderUpdatesController!.stream;
  }

  void _connect(String accessToken) {
    _reconnectTimer?.cancel();

    try {
      final wsUri = Uri.parse('$defaultWsUrl?access_token=$accessToken');

      _channel = IOWebSocketChannel.connect(wsUri);
      _reconnectAttempts = 0; // Reset на успешное подключение

      _channel!.stream.listen(
        (data) {
          _heartbeatTimer?.cancel();
          _startHeartbeat();

          try {
            final jsonData = jsonDecode(data as String);
            if (jsonData is Map<String, dynamic> && jsonData.containsKey('order')) {
              final order = Order.fromMap(jsonData['order'] as Map<String, dynamic>);
              _orderUpdatesController?.add(order);
            }
          } catch (e) {
            debugPrint('Error parsing WebSocket message: $e');
          }
        },
        onError: (error) {
          debugPrint('WebSocket error: $error');
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('WebSocket connection closed');
          _scheduleReconnect();
        },
      );

      _startHeartbeat();
      debugPrint('WebSocket connected successfully');
    } catch (e) {
      debugPrint('Failed to connect WebSocket: $e');
      _scheduleReconnect();
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      try {
        _channel?.sink.add('{"type":"ping"}');
      } catch (e) {
        debugPrint('Heartbeat failed: $e');
        _scheduleReconnect();
      }
    });
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('Max reconnect attempts reached. Stopping reconnection.');
      return;
    }

    _reconnectAttempts++;
    final delay = Duration(seconds: math.min(30, 5 * _reconnectAttempts));

    debugPrint('Scheduling reconnect attempt $_reconnectAttempts in ${delay.inSeconds}s');

    _reconnectTimer = Timer(delay, () {
      if (_currentToken != null) {
        _connect(_currentToken!);
      }
    });
  }

  void _disconnect() {
    _channel?.sink.close();
    _channel = null;
    _orderUpdatesController?.close();
    _orderUpdatesController = null;
    _currentToken = null;
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _disconnect();
  }
}

// Мок WebSocket клиент для тестирования
class MockWebSocketClient implements WebSocketClient {
  StreamController<Order>? _orderUpdatesController;
  StreamController<String>? _messagesController;
  String? _currentToken;
  Timer? _mockOrderUpdatesTimer;
  final _random = math.Random();

  static const _mockStatuses = ['searching', 'assigned', 'onWay', 'arrived', 'evacuating', 'completed'];
  int _statusIndex = 0;

  @override
  Future<void> connect(String url) async {
    debugPrint('[MOCK WS] Connected to $url');
    _messagesController ??= StreamController<String>.broadcast();

    // Имитация успешного подключения через небольшую задержку
    await Future.delayed(const Duration(milliseconds: 200));

    _messagesController?.add('{"type":"connected"}');
  }

  @override
  Stream<String> messages() {
    _messagesController ??= StreamController<String>.broadcast();
    return _messagesController!.stream;
  }

  @override
  Future<void> send(String message) async {
    debugPrint('[MOCK WS] Sending: $message');

    // Имитация ответа на пинг
    if (message.contains('"type":"ping"')) {
      await Future.delayed(const Duration(milliseconds: 100));
      _messagesController?.add('{"type":"pong"}');
    }
  }

  @override
  Future<void> disconnect() async {
    debugPrint('[MOCK WS] Disconnected');
    _mockOrderUpdatesTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    await _messagesController?.close();
    _messagesController = null;
  }

  Stream<Order> watchOrderUpdates({required String accessToken}) {
    if (_orderUpdatesController != null && _currentToken == accessToken) {
      return _orderUpdatesController!.stream;
    }

    _disconnect();
    _currentToken = accessToken;
    _orderUpdatesController = StreamController<Order>.broadcast();

    _startMockOrderUpdates();

    return _orderUpdatesController!.stream;
  }

  void _startMockOrderUpdates() {
    debugPrint('[MOCK WS] Starting mock order updates');

    // Через 2 секунды начинаем отправлять обновления заказов
    Timer(const Duration(seconds: 2), () {
      _mockOrderUpdatesTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        _sendMockOrderUpdate();
      });
    });
  }

  void _sendMockOrderUpdate() {
    if (_orderUpdatesController?.isClosed == true) return;

    final status = _mockStatuses[_statusIndex % _mockStatuses.length];
    _statusIndex++;

    final mockOrder = _generateMockOrder(status);

    debugPrint('[MOCK WS] Sending order update: $status');

    try {
      _orderUpdatesController?.add(mockOrder);

      // Если заказ завершился, останавливаем обновления
      if (status == 'completed' || status == 'cancelled') {
        _mockOrderUpdatesTimer?.cancel();
        _statusIndex = 0; // Сброс для следующего заказа
      }
    } catch (e) {
      debugPrint('[MOCK WS] Error sending mock order: $e');
    }
  }

  Order _generateMockOrder(String statusString) {
    final pickupLat = AppConstants.moscowLat + (_random.nextDouble() - 0.5) * 0.05;
    final pickupLng = AppConstants.moscowLng + (_random.nextDouble() - 0.5) * 0.05;
    final dropoffLat = AppConstants.moscowLat + (_random.nextDouble() - 0.5) * 0.05;
    final dropoffLng = AppConstants.moscowLng + (_random.nextDouble() - 0.5) * 0.05;

    // Преобразование строки в enum
    final status = _parseOrderStatus(statusString);
    final vehicleTypes = [VehicleType.light, VehicleType.suv, VehicleType.minibus, VehicleType.truck];
    final paymentMethods = [PaymentMethod.cash, PaymentMethod.card];

    return Order(
      id: 'mock_order_${_random.nextInt(9999)}',
      clientId: 'mock_client_123',
      driverId: status != OrderStatus.searching ? 'mock_driver_456' : null,
      status: status,
      vehicleType: vehicleTypes[_random.nextInt(vehicleTypes.length)],
      pickupLocation: LocationModel(
        lat: pickupLat,
        lng: pickupLng,
        address: 'Тестовая улица, ${_random.nextInt(100) + 1}',
      ),
      dropoffLocation: LocationModel(
        lat: dropoffLat,
        lng: dropoffLng,
        address: 'Тестовая улица, ${_random.nextInt(200) + 100}',
      ),
      estimatedPrice: (800 + _random.nextInt(2000)).toDouble(),
      distance: (5 + _random.nextInt(45)).toDouble(),
      paymentMethod: paymentMethods[_random.nextInt(paymentMethods.length)],
      createdAt: DateTime.now(),
    );
  }

  OrderStatus _parseOrderStatus(String statusString) {
    return switch (statusString) {
      'searching' => OrderStatus.searching,
      'assigned' => OrderStatus.assigned,
      'onWay' => OrderStatus.onWay,
      'arrived' => OrderStatus.arrived,
      'evacuating' => OrderStatus.evacuating,
      'completed' => OrderStatus.completed,
      'cancelled' => OrderStatus.cancelled,
      _ => OrderStatus.searching,
    };
  }

  WebSocketChannel? _channel; // Добавляем для совместимости

  void _disconnect() {
    _mockOrderUpdatesTimer?.cancel();
    _orderUpdatesController?.close();
    _orderUpdatesController = null;
    _currentToken = null;
  }

  void dispose() {
    _mockOrderUpdatesTimer?.cancel();
    _disconnect();
  }
}
