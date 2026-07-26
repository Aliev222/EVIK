import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'websocket_client.dart';

class Event {
  const Event({
    required this.type,
    required this.orderId,
    this.payload,
  });

  final String type;
  final String orderId;
  final Object? payload;
}

abstract class EventDispatcher {
  Future<void> start();
  Stream<Event> events();
  Stream<Event> orderEvents(String orderId);
  void handleEvent(Event event);
  Future<void> stop();
  Stream<void> get onReconnected;
}

class WsEventDispatcher implements EventDispatcher {
  WsEventDispatcher({
    required WebSocketClient client,
    required String wsUrl,
  })  : _client = client,
        _wsUrl = wsUrl;

  final WebSocketClient _client;
  final String _wsUrl;
  final StreamController<Event> _orderEvents =
      StreamController<Event>.broadcast();
  StreamSubscription<String>? _subscription;
  bool _started = false;

  @override
  Stream<void> get onReconnected => _client.onReconnected;

  @override
  Future<void> start() async {
    if (_started) return;
    await _client.connect(_wsUrl);
    _started = true;
    _subscription = _client.messages().listen((raw) {
      try {
        final dynamic decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final orderId = decoded['order_id']?.toString();
          final type = decoded['type']?.toString();
          if (orderId != null && type != null) {
            final payload = decoded['payload'] ?? decoded;
            handleEvent(
              Event(
                type: type,
                orderId: orderId,
                payload: payload,
              ),
            );
          }
        }
      } catch (_) {
        // Ignore malformed payloads.
      }
    });
  }

  @override
  Stream<Event> events() {
    return _orderEvents.stream;
  }

  @override
  Stream<Event> orderEvents(String orderId) {
    return _orderEvents.stream.where((event) => event.orderId == orderId);
  }

  @override
  void handleEvent(Event event) {
    switch (event.type) {
      case 'order_created':
      case 'searching':
      case 'order_accepted':
      case 'order_arrived':
      case 'in_progress':
      case 'awaiting_payment':
      case 'completed':
      case 'cancelled':
      case 'no_driver_found':
      case 'order_expanded':
      case 'payment_method_changed':
        debugPrint('WS event dispatched: type=${event.type} orderId=${event.orderId}');
        _orderEvents.add(event);
        break;
      case 'offer':
        debugPrint('WS offer received: orderId=${event.orderId}');
        _orderEvents.add(event);
        break;
      default:
        debugPrint('WS event ignored (unknown type): ${event.type}');
        break;
    }
  }

  @override
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _client.disconnect();
    _started = false;
  }
}
