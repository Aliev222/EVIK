import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:tow_truck_frontend/core/realtime/event_dispatcher.dart';
import 'package:tow_truck_frontend/features/chat/data/chat_repository.dart';
import 'package:tow_truck_frontend/features/chat/domain/chat_message.dart';

class ChatState {
  const ChatState(
      {this.messages = const [],
      this.loading = false,
      this.loadingMore = false,
      this.readOnly = false,
      this.nextBeforeId,
      this.error});
  final List<ChatMessage> messages;
  final bool loading;
  final bool loadingMore;
  final bool readOnly;
  final String? nextBeforeId;
  final String? error;
  ChatState copyWith(
          {List<ChatMessage>? messages,
          bool? loading,
          bool? loadingMore,
          bool? readOnly,
          String? nextBeforeId,
          bool clearNext = false,
          String? error,
          bool clearError = false}) =>
      ChatState(
          messages: messages ?? this.messages,
          loading: loading ?? this.loading,
          loadingMore: loadingMore ?? this.loadingMore,
          readOnly: readOnly ?? this.readOnly,
          nextBeforeId: clearNext ? null : nextBeforeId ?? this.nextBeforeId,
          error: clearError ? null : error ?? this.error);
}

class ChatController extends StateNotifier<ChatState> {
  ChatController(this.orderId, this.repo, {required bool readOnly})
      : super(ChatState(readOnly: readOnly)) {
    _events = repo.dispatcher.orderEvents(orderId).listen(_onEvent);
    _reconnect = repo.dispatcher.onReconnected.listen((_) => unawaited(load()));
    unawaited(load());
  }
  final String orderId;
  final ChatDataSource repo;
  late final StreamSubscription<Event> _events;
  late final StreamSubscription<void> _reconnect;
  final _uuid = const Uuid();
  bool _disposed = false;

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final page = await repo.history(orderId);
      if (_disposed) return;
      state = state.copyWith(
          messages: _merge(page.messages),
          nextBeforeId: page.nextBeforeId,
          loading: false);
      await repo.subscribe(orderId);
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.loadingMore || state.nextBeforeId == null) return;
    state = state.copyWith(loadingMore: true);
    try {
      final page = await repo.history(orderId, beforeId: state.nextBeforeId);
      if (_disposed) return;
      state = state.copyWith(
          messages: _merge(page.messages),
          nextBeforeId: page.nextBeforeId,
          loadingMore: false);
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(loadingMore: false, error: e.toString());
    }
  }

  Future<void> send(String text, {String? clientMessageId}) async {
    if (state.readOnly || text.trim().isEmpty) return;
    final id = clientMessageId ?? _uuid.v7();
    final pending = ChatMessage(
        id: 'client:$id',
        orderId: orderId,
        senderId: 'me',
        clientMessageId: id,
        text: text.trim(),
        createdAt: DateTime.now(),
        status: ChatMessageStatus.pending);
    state = state.copyWith(messages: _merge([...state.messages, pending]));
    if (_disposed) return;
    try {
      await repo.sendRealtime(orderId, id, text.trim());
    } catch (_) {
      if (_disposed) return;
      try {
        final sent = await repo.send(orderId, id, text.trim());
        if (_disposed) return;
        state = state.copyWith(messages: _merge([...state.messages, sent]));
      } catch (_) {
        if (_disposed) return;
        state = state.copyWith(
            messages: state.messages
                .map((m) => m.clientMessageId == id
                    ? m.copyWith(status: ChatMessageStatus.failed)
                    : m)
                .toList(),
            error: 'Не удалось отправить сообщение');
      }
    }
  }

  Future<void> retry(ChatMessage message) =>
      send(message.text, clientMessageId: message.clientMessageId);
  List<ChatMessage> _merge(Iterable<ChatMessage> incoming) {
    final byId = <String, ChatMessage>{for (final m in state.messages) m.id: m};
    for (final m in incoming) {
      final old = byId[m.id];
      byId[m.id] = m;
      if (old != null && old.clientMessageId.isNotEmpty) byId.remove(old.id);
    }
    final byClient = <String, ChatMessage>{};
    for (final m in byId.values) {
      byClient[m.clientMessageId] = m;
    }
    return byClient.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  void _onEvent(Event event) {
    final payload = event.payload;
    if (payload is! Map<String, dynamic>) return;
    final raw = payload['message'];
    if (raw is Map<String, dynamic>) {
      state = state.copyWith(messages: _merge([ChatMessage.fromJson(raw)]));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(repo.unsubscribe(orderId));
    _events.cancel();
    _reconnect.cancel();
    super.dispose();
  }
}
