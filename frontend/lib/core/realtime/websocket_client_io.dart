import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'websocket_client.dart';

WebSocketClient createPlatformWebSocketClient() {
  return ChannelWebSocketClient();
}

class ChannelWebSocketClient implements WebSocketClient {
  WebSocketChannel? _channel;
  StreamController<String>? _messages;
  StreamSubscription<dynamic>? _subscription;
  final StreamController<WebSocketConnectionStatus> _connectionStatusController =
      StreamController<WebSocketConnectionStatus>.broadcast();
  final StreamController<void> _onReconnectedController =
      StreamController<void>.broadcast();
  String? _url;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  bool _intentionalDisconnect = false;

  @override
  Stream<WebSocketConnectionStatus> get connectionStatus =>
      _connectionStatusController.stream;

  @override
  Stream<void> get onReconnected => _onReconnectedController.stream;

  @override
  Future<void> connect(String url) async {
    _intentionalDisconnect = false;
    _url = url;
    _reconnectAttempt = 0;
    _reconnectTimer?.cancel();
    await disconnect();
    _messages = StreamController<String>.broadcast();
    _channel = WebSocketChannel.connect(Uri.parse(url));
    _connectionStatusController.add(WebSocketConnectionStatus.connected);
    _subscription = _channel!.stream.listen(
      (dynamic message) {
        if (message is String) {
          _messages?.add(message);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _pingTimer?.cancel();
        _messages?.addError(error, stackTrace);
        _connectionStatusController.add(WebSocketConnectionStatus.disconnected);
        _scheduleReconnect();
      },
      onDone: () {
        _pingTimer?.cancel();
        final controller = _messages;
        if (controller != null && !controller.isClosed) {
          controller.close();
        }
        _connectionStatusController.add(WebSocketConnectionStatus.disconnected);
        if (!_intentionalDisconnect) {
          _scheduleReconnect();
        }
      },
    );
    _startPingTimer();
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _channel?.sink.add('HEARTBEAT');
    });
  }

  @override
  Stream<String> messages() =>
      _messages?.stream ?? const Stream<String>.empty();

  @override
  Future<void> send(String message) async {
    _channel?.sink.add(message);
  }

  @override
  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    final channel = _channel;
    final controller = _messages;
    final subscription = _subscription;
    _channel = null;
    _messages = null;
    _subscription = null;
    await subscription?.cancel();
    if (channel != null) {
      await channel.sink.close();
    }
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
    _connectionStatusController.add(WebSocketConnectionStatus.disconnected);
  }

  void _scheduleReconnect() {
    if (_url == null || _intentionalDisconnect) return;
    _reconnectAttempt++;
    final delay = Duration(
      milliseconds: (_reconnectAttempt <= 6)
          ? (1000 * (1 << (_reconnectAttempt - 1))).clamp(1000, 30000)
          : 30000,
    );
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      _connectionStatusController.add(WebSocketConnectionStatus.connecting);
      connect(_url!).then((_) {
        _reconnectAttempt = 0;
        _onReconnectedController.add(null);
      }).catchError((_) {
        _scheduleReconnect();
      });
    });
  }
}
