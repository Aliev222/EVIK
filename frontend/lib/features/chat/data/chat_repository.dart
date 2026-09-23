import 'dart:convert';

import 'package:tow_truck_frontend/core/network/api_client.dart';
import 'package:tow_truck_frontend/core/realtime/event_dispatcher.dart';
import 'package:tow_truck_frontend/core/realtime/websocket_client.dart';
import 'package:tow_truck_frontend/features/chat/domain/chat_message.dart';

class ChatPage {
  const ChatPage(this.messages, this.nextBeforeId);
  final List<ChatMessage> messages;
  final String? nextBeforeId;
}

abstract interface class ChatDataSource {
  EventDispatcher get dispatcher;
  Future<ChatPage> history(String orderId, {String? beforeId, int limit = 50});
  Future<ChatMessage> send(String orderId, String clientMessageId, String text);
  Future<void> subscribe(String orderId);
  Future<void> unsubscribe(String orderId);
  Future<void> sendRealtime(
      String orderId, String clientMessageId, String text);
}

class ChatRepository implements ChatDataSource {
  ChatRepository(
      {required this.api,
      required this.dispatcher,
      required this.client,
      this.tokenProvider});
  final ApiClient api;
  @override
  final EventDispatcher dispatcher;
  final WebSocketClient client;
  final String? Function()? tokenProvider;

  Map<String, String>? get _headers {
    final token = tokenProvider?.call();
    return token == null || token.isEmpty
        ? null
        : {'Authorization': 'Bearer $token'};
  }

  @override
  Future<ChatPage> history(String orderId,
      {String? beforeId, int limit = 50}) async {
    final query = <String, String>{
      'limit': '$limit',
      if (beforeId != null) 'before_id': beforeId
    };
    final response = await api.get(
        '/api/v1/orders/$orderId/chat/messages?${Uri(queryParameters: query).query}',
        headers: _headers);
    final raw = (response['messages'] as List<dynamic>? ?? const <dynamic>[]);
    return ChatPage(
        raw
            .whereType<Map<String, dynamic>>()
            .map(ChatMessage.fromJson)
            .toList(),
        response['next_before_id']?.toString());
  }

  @override
  Future<ChatMessage> send(
      String orderId, String clientMessageId, String text) async {
    final response = await api.post('/api/v1/orders/$orderId/chat/messages',
        {'client_message_id': clientMessageId, 'text': text},
        headers: _headers);
    return ChatMessage.fromJson(response['message'] as Map<String, dynamic>);
  }

  @override
  Future<void> subscribe(String orderId) => client.send(jsonEncode({
        'type': 'chat.subscribe',
        'data': {'order_id': orderId}
      }));
  @override
  Future<void> unsubscribe(String orderId) => client.send(jsonEncode({
        'type': 'chat.unsubscribe',
        'data': {'order_id': orderId}
      }));
  @override
  Future<void> sendRealtime(
          String orderId, String clientMessageId, String text) =>
      client.send(jsonEncode({
        'type': 'chat.send',
        'data': {
          'order_id': orderId,
          'client_message_id': clientMessageId,
          'text': text
        }
      }));
}
