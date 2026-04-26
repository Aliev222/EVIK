import 'dart:async';

abstract class WebSocketClient {
  Future<void> connect(String url);
  Stream<String> messages();
  Future<void> send(String message);
  Future<void> disconnect();
}

const defaultWsUrl = String.fromEnvironment(
  'EVIK_WS_URL',
  defaultValue: 'ws://localhost:8080/ws/orders',
);

class InMemoryWebSocketClient implements WebSocketClient {
  final StreamController<String> _messages =
      StreamController<String>.broadcast();
  bool _connected = false;

  @override
  Future<void> connect(String url) async {
    _connected = true;
  }

  @override
  Stream<String> messages() => _messages.stream;

  @override
  Future<void> send(String message) async {
    if (!_connected) return;
    _messages.add(message);
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    await _messages.close();
  }
}
