import 'dart:async';
import 'dart:convert';

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
  Stream<Event> orderEvents(String orderId);
  void handleEvent(Event event);
  Future<void> stop();
}

class WsEventDispatcher implements EventDispatcher {
  WsEventDispatcher({
    required WebSocketClient client,
    required String wsUrl,
  })  : _client = client,
        _wsUrl = wsUrl;

  final WebSocketClient _client;
  final String _wsUrl;
  final StreamController<Event> _orderEvents = StreamController<Event>.broadcast();
  StreamSubscription<String>? _subscription;

  @override
  Future<void> start() async {
    await _client.connect(_wsUrl);
    _subscription = _client.messages().listen((raw) {
      try {
        final dynamic decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final orderId = decoded['order_id']?.toString();
          final type = decoded['type']?.toString();
          if (orderId != null && type != null) {
            handleEvent(
              Event(
                type: type,
                orderId: orderId,
                payload: decoded['payload'],
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
      case 'completed':
      case 'cancelled':
      case 'no_driver_found':
        // TODO: Route event into feature-specific state handlers.
        _orderEvents.add(event);
        break;
      default:
        break;
    }
  }

  @override
  Future<void> stop() async {
    await _subscription?.cancel();
    await _client.disconnect();
    await _orderEvents.close();
  }
}
