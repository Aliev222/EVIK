import 'dart:async';
import 'dart:io';

import 'websocket_client.dart';

WebSocketClient createPlatformWebSocketClient() {
  return IoWebSocketClient();
}

class IoWebSocketClient implements WebSocketClient {
  WebSocket? _socket;
  StreamController<String>? _messages;

  @override
  Future<void> connect(String url) async {
    await disconnect();
    _messages = StreamController<String>.broadcast();
    _socket = await WebSocket.connect(url);
    _socket!.listen(
      (dynamic message) {
        if (message is String) {
          _messages?.add(message);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _messages?.addError(error, stackTrace);
      },
      onDone: () {
        final controller = _messages;
        if (controller != null && !controller.isClosed) {
          controller.close();
        }
      },
    );
  }

  @override
  Stream<String> messages() => _messages?.stream ?? const Stream<String>.empty();

  @override
  Future<void> send(String message) async {
    _socket?.add(message);
  }

  @override
  Future<void> disconnect() async {
    final socket = _socket;
    final controller = _messages;
    _socket = null;
    _messages = null;
    if (socket != null) {
      await socket.close();
    }
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
  }
}
