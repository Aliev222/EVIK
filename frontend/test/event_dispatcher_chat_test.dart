import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tow_truck_frontend/core/realtime/event_dispatcher.dart';
import 'package:tow_truck_frontend/core/realtime/websocket_client.dart';

void main() {
  test('dispatcher routes chat events and derives order id from message',
      () async {
    final client = InMemoryWebSocketClient();
    final dispatcher = WsEventDispatcher(client: client, wsUrl: 'ws://test');
    final events = <Event>[];
    final sub = dispatcher.events().listen(events.add);
    await dispatcher.start();
    await client.send(jsonEncode({
      'type': 'chat.message',
      'payload': {
        'message': {'order_id': 'o1', 'id': 'm1', 'text': 'hi'}
      },
    }));
    await Future<void>.delayed(Duration.zero);
    expect(events.single.type, 'chat.message');
    expect(events.single.orderId, 'o1');
    await sub.cancel();
    await dispatcher.stop();
  });

  test('malformed and unknown events do not reach subscribers', () async {
    final client = InMemoryWebSocketClient();
    final dispatcher = WsEventDispatcher(client: client, wsUrl: 'ws://test');
    final events = <Event>[];
    final sub = dispatcher.events().listen(events.add);
    await dispatcher.start();
    await client.send('{bad');
    await client.send(jsonEncode({'type': 'unknown', 'order_id': 'o1'}));
    await Future<void>.delayed(Duration.zero);
    expect(events, isEmpty);
    await sub.cancel();
    await dispatcher.stop();
  });
}
