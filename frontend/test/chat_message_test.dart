import 'package:flutter_test/flutter_test.dart';
import 'package:tow_truck_frontend/features/chat/domain/chat_message.dart';

void main() {
  test('ChatMessage parses and serializes server JSON', () {
    final message = ChatMessage.fromJson({
      'id': 'm1',
      'order_id': 'o1',
      'sender_id': 'u1',
      'client_message_id': 'c1',
      'text': 'Привет',
      'created_at': '2026-09-16T10:00:00Z',
    });
    expect(message.orderId, 'o1');
    expect(message.text, 'Привет');
    expect(ChatMessage.fromJson(message.toJson()).clientMessageId, 'c1');
  });

  test('failed message preserves client id for retry', () {
    final message = ChatMessage.fromJson({
      'id': 'm1',
      'order_id': 'o1',
      'sender_id': 'u1',
      'client_message_id': 'c1',
      'text': 'x',
    }, status: ChatMessageStatus.failed);
    expect(message.copyWith(status: ChatMessageStatus.pending).clientMessageId,
        'c1');
  });
}
