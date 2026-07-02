import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'websocket_client.dart';

const defaultWsUrl = String.fromEnvironment(
  'EVIK_WS_URL',
  defaultValue: 'wss://tow-truck.onrender.com/ws/orders',
);

WebSocketClient createPlatformWebSocketClient() {
  return IoWebSocketClient();
}

class IoWebSocketClient implements WebSocketClient {
  WebSocketChannel? _channel;
  StreamController<Order>? _orderUpdatesController;
  StreamController<String>? _messagesController;
  String? _currentToken;
  String? _wsUrl;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  int _reconnectAttempts = 0;
  bool _shouldReconnect = true;
  bool _wasConnectedBefore = false;
  final math.Random _random = math.Random();

  final StreamController<WebSocketConnectionStatus> _connectionStatusController =
      StreamController<WebSocketConnectionStatus>.broadcast();
  final StreamController<void> _onReconnectedController =
      StreamController<void>.broadcast();

  @override
  Stream<WebSocketConnectionStatus> get connectionStatus =>
      _connectionStatusController.stream;

  @override
  Stream<void> get onReconnected => _onReconnectedController.stream;

  @override
  Future<void> connect(String url) async {
    _wsUrl = url;
    _shouldReconnect = true;
    _reconnectAttempts = 0;
    _connectionStatusController.add(WebSocketConnectionStatus.connecting);
    _doConnect();
  }

  void _doConnect() {
    if (_wsUrl == null) return;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();

    try {
      final wsUri = Uri.parse(_wsUrl!);
      _channel = IOWebSocketChannel.connect(wsUri);
      _reconnectAttempts = 0;

      _messagesController ??= StreamController<String>.broadcast();

      _connectionStatusController.add(WebSocketConnectionStatus.connected);
      if (_wasConnectedBefore) {
        _onReconnectedController.add(null);
      }
      _wasConnectedBefore = true;

      _channel!.stream.listen(
        (data) {
          _heartbeatTimer?.cancel();
          _startHeartbeat();
          _messagesController?.add(data as String);
        },
        onError: (error) {
          debugPrint('WebSocket error: $error');
          _connectionStatusController.add(WebSocketConnectionStatus.disconnected);
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('WebSocket connection closed');
          _connectionStatusController.add(WebSocketConnectionStatus.disconnected);
          _scheduleReconnect();
        },
      );

      _startHeartbeat();
      debugPrint('WebSocket connected successfully');
    } catch (e) {
      debugPrint('Failed to connect WebSocket: $e');
      _connectionStatusController.add(WebSocketConnectionStatus.disconnected);
      _scheduleReconnect();
    }
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
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    await _messagesController?.close();
    _messagesController = null;
    _connectionStatusController.add(WebSocketConnectionStatus.disconnected);
    _wsUrl = null;
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
    _currentToken = accessToken;

    try {
      final wsUri = Uri.parse('$defaultWsUrl?access_token=$accessToken');

      _channel = IOWebSocketChannel.connect(wsUri);
      _reconnectAttempts = 0;

      _channel!.stream.listen(
        (data) {
          _heartbeatTimer?.cancel();
          _startHeartbeat();

          try {
            final jsonData = jsonDecode(data as String);
            if (jsonData is! Map<String, dynamic>) return;

            debugPrint('WS raw data: ${jsonData['type']}');

            final Map<String, dynamic>? payload =
                jsonData['payload'] as Map<String, dynamic>?;
            final Map<String, dynamic>? orderData =
                payload?['order'] as Map<String, dynamic>?;
            final Map<String, dynamic>? orderDataLegacy =
                jsonData['order'] as Map<String, dynamic>?;

            final Map<String, dynamic>? finalOrderData =
                orderData ?? orderDataLegacy;

            if (finalOrderData != null) {
              final order =
                  Order.fromMap(finalOrderData);
              _orderUpdatesController?.add(order);
              debugPrint('WS order update: ${order.id} status=${order.state}');
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
        if (_shouldReconnect) {
          _connectionStatusController.add(WebSocketConnectionStatus.disconnected);
          _scheduleReconnect();
        }
      }
    });
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect) return;

    _reconnectTimer?.cancel();
    _reconnectAttempts++;

    final baseDelay = math.min(30, 1 << (_reconnectAttempts - 1));
    final jitter = _random.nextDouble();
    final totalDelay = Duration(
      seconds: baseDelay,
      milliseconds: (jitter * 1000).toInt(),
    );

    debugPrint(
      'Scheduling reconnect attempt $_reconnectAttempts in ${totalDelay.inSeconds}s (base: ${baseDelay}s)',
    );

    _connectionStatusController.add(WebSocketConnectionStatus.connecting);

    _reconnectTimer = Timer(totalDelay, () {
      if (!_shouldReconnect) return;
      if (_currentToken != null) {
        _connect(_currentToken!);
      } else if (_wsUrl != null) {
        _doConnect();
      }
    });
  }

  void _disconnect() {
    _shouldReconnect = false;
    _channel?.sink.close();
    _channel = null;
    _orderUpdatesController?.close();
    _orderUpdatesController = null;
    _currentToken = null;
  }

  void dispose() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _disconnect();
    _connectionStatusController.close();
    _onReconnectedController.close();
  }
}
