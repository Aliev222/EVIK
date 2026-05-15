import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../features/order/domain/entities/order.dart';
import 'websocket_client.dart';

const defaultWsUrl = String.fromEnvironment(
  'EVIK_WS_URL',
  defaultValue: 'wss://evik-backend.onrender.com/ws/orders',
);

WebSocketClient createPlatformWebSocketClient() {
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
      _reconnectAttempts = 0;

      _channel!.stream.listen(
        (data) {
          _heartbeatTimer?.cancel();
          _startHeartbeat();

          try {
            final jsonData = jsonDecode(data as String);
            if (jsonData is Map<String, dynamic> &&
                jsonData.containsKey('order')) {
              final order =
                  Order.fromMap(jsonData['order'] as Map<String, dynamic>);
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
    debugPrint(
      'Scheduling reconnect attempt $_reconnectAttempts in ${delay.inSeconds}s',
    );

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
