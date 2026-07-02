import 'dart:async';

enum WebSocketConnectionStatus { disconnected, connecting, connected }

abstract class WebSocketClient {
  Future<void> connect(String url);
  Stream<String> messages();
  Future<void> send(String message);
  Future<void> disconnect();

  Stream<WebSocketConnectionStatus> get connectionStatus;
  Stream<void> get onReconnected;
}

const defaultWsUrl = String.fromEnvironment(
  'EVIK_WS_URL',
  defaultValue: 'wss://tow-truck.onrender.com/ws/orders',
);

class InMemoryWebSocketClient implements WebSocketClient {
  final StreamController<String> _messages =
      StreamController<String>.broadcast();
  final StreamController<WebSocketConnectionStatus> _connectionStatusController =
      StreamController<WebSocketConnectionStatus>.broadcast();
  final StreamController<void> _onReconnectedController =
      StreamController<void>.broadcast();
  bool _connected = false;

  @override
  Stream<WebSocketConnectionStatus> get connectionStatus =>
      _connectionStatusController.stream;

  @override
  Stream<void> get onReconnected => _onReconnectedController.stream;

  @override
  Future<void> connect(String url) async {
    _connected = true;
    _connectionStatusController.add(WebSocketConnectionStatus.connected);
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
    _connectionStatusController.add(WebSocketConnectionStatus.disconnected);
    await _messages.close();
  }
}
