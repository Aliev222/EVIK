import 'websocket_client.dart';

WebSocketClient createPlatformWebSocketClient() {
  return InMemoryWebSocketClient();
}
