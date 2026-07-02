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

  @override
  Stream<WebSocketConnectionStatus> get connectionStatus =>
      _connectionStatusController.stream;

  @override
  Stream<void> get onReconnected => _onReconnectedController.stream;

  @override
  Future<void> connect(String url) async {
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
        _messages?.addError(error, stackTrace);
        _connectionStatusController.add(WebSocketConnectionStatus.disconnected);
      },
      onDone: () {
        final controller = _messages;
        if (controller != null && !controller.isClosed) {
          controller.close();
        }
        _connectionStatusController.add(WebSocketConnectionStatus.disconnected);
      },
    );
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
}
