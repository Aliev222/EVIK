enum ChatMessageStatus { pending, sent, failed }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.orderId,
    required this.senderId,
    required this.clientMessageId,
    required this.text,
    required this.createdAt,
    this.recipientId,
    this.status = ChatMessageStatus.sent,
  });

  final String id;
  final String orderId;
  final String senderId;
  final String? recipientId;
  final String clientMessageId;
  final String text;
  final DateTime createdAt;
  final ChatMessageStatus status;

  factory ChatMessage.fromJson(Map<String, dynamic> json,
      {ChatMessageStatus? status}) {
    return ChatMessage(
      id: json['id']?.toString() ?? 'client:${json['client_message_id']}',
      orderId: json['order_id']?.toString() ?? '',
      senderId: json['sender_id']?.toString() ?? '',
      recipientId: json['recipient_id']?.toString(),
      clientMessageId: json['client_message_id']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      status: status ?? ChatMessageStatus.sent,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'order_id': orderId,
        'sender_id': senderId,
        'recipient_id': recipientId,
        'client_message_id': clientMessageId,
        'text': text,
        'created_at': createdAt.toIso8601String(),
      };

  ChatMessage copyWith({String? id, ChatMessageStatus? status}) => ChatMessage(
        id: id ?? this.id,
        orderId: orderId,
        senderId: senderId,
        recipientId: recipientId,
        clientMessageId: clientMessageId,
        text: text,
        createdAt: createdAt,
        status: status ?? this.status,
      );
}
