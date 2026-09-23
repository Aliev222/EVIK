import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tow_truck_frontend/core/realtime/event_dispatcher.dart'
    as realtime;
import 'package:tow_truck_frontend/features/chat/data/chat_repository.dart';
import 'package:tow_truck_frontend/features/chat/domain/chat_message.dart';
import 'package:tow_truck_frontend/features/chat/presentation/chat_controller.dart';

class FakeChatSource implements ChatDataSource {
  FakeChatSource() : dispatcher = FakeDispatcher();
  @override
  final realtime.EventDispatcher dispatcher;
  final pages = <Completer<ChatPage>>[];
  int historyCalls = 0;
  final sent = <String>[];
  final subscriptions = <String>[];
  final secondSubscription = Completer<void>();
  @override
  Future<ChatPage> history(String orderId, {String? beforeId, int limit = 50}) {
    historyCalls++;
    final page = Completer<ChatPage>();
    pages.add(page);
    return page.future;
  }

  @override
  Future<ChatMessage> send(String orderId, String id, String text) async =>
      ChatMessage(
          id: 'server-$id',
          orderId: orderId,
          senderId: 'me',
          clientMessageId: id,
          text: text,
          createdAt: DateTime.now());
  @override
  Future<void> subscribe(String orderId) async {
    subscriptions.add('sub:$orderId');
    if (subscriptions.where((x) => x == 'sub:$orderId').length == 2 &&
        !secondSubscription.isCompleted) {
      secondSubscription.complete();
    }
  }

  @override
  Future<void> unsubscribe(String orderId) async =>
      subscriptions.add('unsub:$orderId');
  @override
  Future<void> sendRealtime(String orderId, String id, String text) async =>
      sent.add(id);
}

class FakeDispatcher implements realtime.EventDispatcher {
  final eventController =
      StreamController<realtime.Event>.broadcast(sync: true);
  final reconnectController = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get onReconnected => reconnectController.stream;
  @override
  Stream<realtime.Event> events() => eventController.stream;
  @override
  Stream<realtime.Event> orderEvents(String id) =>
      eventController.stream.where((e) => e.orderId == id);
  @override
  void handleEvent(realtime.Event event) => eventController.add(event);
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {
    await eventController.close();
    await reconnectController.close();
  }
}

ChatMessage message(String id, String clientId, String text) => ChatMessage(
    id: id,
    orderId: 'o1',
    senderId: 'u1',
    clientMessageId: clientId,
    text: text,
    createdAt: DateTime.utc(2026, 1, 1));

void main() {
  test('loads history and sends optimistic message with stable retry id',
      () async {
    final source = FakeChatSource();
    final controller = ChatController('o1', source, readOnly: false);
    expect(controller.state.loading, isTrue);
    source.pages.single
        .complete(ChatPage([message('m1', 'c1', 'hello')], null));
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.messages.single.text, 'hello');
    await controller.send('outgoing');
    expect(source.sent, hasLength(1));
    final id = source.sent.single;
    expect(
        controller.state.messages.any((m) => m.clientMessageId == id), isTrue);
    await controller.retry(controller.state.messages.last);
    expect(source.sent.last, id);
    controller.dispose();
    await (source.dispatcher as FakeDispatcher).stop();
  });

  test('reconnect resubscribes and catches up without duplicate listeners',
      () async {
    final source = FakeChatSource();
    final controller = ChatController('o1', source, readOnly: false);
    source.pages.single.complete(const ChatPage([], null));
    await Future<void>.delayed(Duration.zero);
    final dispatcher = source.dispatcher as FakeDispatcher;
    expect(source.subscriptions.where((x) => x == 'sub:o1'), hasLength(1));
    dispatcher.reconnectController.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(source.pages, hasLength(2));
    source.pages.last
        .complete(ChatPage([message('m2', 'c2', 'catch-up')], null));
    await source.secondSubscription.future;
    expect(source.subscriptions.where((x) => x == 'sub:o1'), hasLength(2));
    expect(source.historyCalls, 2);
    expect(controller.state.messages.single.text, 'catch-up');
    controller.dispose();
    await dispatcher.stop();
  });

  test('closed controller ignores late history and does not send', () async {
    final source = FakeChatSource();
    final controller = ChatController('o1', source, readOnly: true);
    controller.dispose();
    source.pages.single.complete(ChatPage([message('m1', 'c1', 'late')], null));
    await Future<void>.delayed(Duration.zero);
    expect(source.sent, isEmpty);
    await (source.dispatcher as FakeDispatcher).stop();
  });
}
