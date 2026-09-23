import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tow_truck_frontend/features/chat/presentation/chat_screen.dart';
import 'package:tow_truck_frontend/features/chat/presentation/chat_controller.dart';
import 'package:tow_truck_frontend/features/chat/domain/chat_message.dart';

ChatMessage msg(String id, String sender, String text,
        {ChatMessageStatus status = ChatMessageStatus.sent}) =>
    ChatMessage(
        id: id,
        orderId: 'o1',
        senderId: sender,
        clientMessageId: 'c$id',
        text: text,
        createdAt: DateTime.utc(2026),
        status: status);

void main() {
  testWidgets('audit fixture renders a message without production network',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ChatScreen(
          orderId: 'audit-order', title: 'Водитель', auditDemo: true),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Буду у машины через несколько минут.'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('read-only chat does not render a composer', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ChatScreen(
          orderId: 'closed-order',
          title: 'Клиент',
          readOnly: true,
          auditDemo: true),
    ));
    await tester.pumpAndSettle();
    expect(
        find.text('Чат закрыт для отправки новых сообщений'), findsOneWidget);
  });

  testWidgets('loading state shows progress', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: ChatScreen(
            orderId: 'o1',
            title: 'Chat',
            testState: ChatState(loading: true))));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('empty state is shown without messages', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home:
            ChatScreen(orderId: 'o1', title: 'Chat', testState: ChatState())));
    expect(find.text('Сообщений пока нет'), findsOneWidget);
  });

  testWidgets('incoming message is left-aligned and renders Unicode',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: ChatScreen(
            orderId: 'o1',
            title: 'Chat',
            testState:
                ChatState(messages: [msg('1', 'driver', 'Привет 🚗')]))));
    expect(
        tester
            .widget<Align>(find
                .ancestor(
                    of: find.text('Привет 🚗'), matching: find.byType(Align))
                .first)
            .alignment,
        Alignment.centerLeft);
  });

  testWidgets('outgoing message is right-aligned', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: ChatScreen(
            orderId: 'o1',
            title: 'Chat',
            testState: ChatState(messages: [msg('2', 'me', 'Еду')]))));
    expect(
        tester
            .widget<Align>(find
                .ancestor(of: find.text('Еду'), matching: find.byType(Align))
                .first)
            .alignment,
        Alignment.centerRight);
  });

  testWidgets('pending message shows indicator', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: ChatScreen(
            orderId: 'o1',
            title: 'Chat',
            testState: ChatState(messages: [
              msg('2', 'me', 'Еду', status: ChatMessageStatus.pending)
            ]))));
    expect(find.text('Еду'), findsOneWidget);
    expect(find.text('Отправляется…'), findsOneWidget);
  });

  testWidgets('failed message exposes retry action', (tester) async {
    var retried = false;
    await tester.pumpWidget(MaterialApp(
        home: ChatScreen(
            orderId: 'o1',
            title: 'Chat',
            testState: ChatState(messages: [
              msg('3', 'me', 'Ошибка', status: ChatMessageStatus.failed)
            ]),
            onTestRetry: (_) => retried = true)));
    expect(find.text('Повторить'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    expect(retried, isTrue);
  });

  testWidgets('reconnect indicator preserves existing messages',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: ChatScreen(
            orderId: 'o1',
            title: 'Chat',
            testState: ChatState(
                loading: true, messages: [msg('1', 'driver', 'Сохранено')]))));
    expect(find.text('Сохранено'), findsOneWidget);
    expect(find.text('Восстанавливаем соединение…'), findsOneWidget);
  });

  testWidgets('rate-limit error is visible', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: ChatScreen(
            orderId: 'o1',
            title: 'Chat',
            testState: ChatState(error: 'rate_limited'))));
    expect(find.text('rate_limited'), findsOneWidget);
  });

  testWidgets('forbidden error is visible', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: ChatScreen(
            orderId: 'o1',
            title: 'Chat',
            testState: ChatState(error: 'forbidden'))));
    expect(find.text('forbidden'), findsOneWidget);
  });

  testWidgets(
      'active production composer sends trimmed text and ignores whitespace',
      (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: ChatScreen(
            orderId: 'o1',
            title: 'Chat',
            testState: const ChatState(),
            onTestSend: sent.add)));
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.byIcon(Icons.send));
    expect(sent, isEmpty);
    await tester.enterText(find.byType(TextField), '  Unicode Привет  ');
    await tester.tap(find.byIcon(Icons.send));
    expect(sent, ['Unicode Привет']);
  });

  testWidgets('error state and read-only mode render without composer',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: ChatScreen(
            orderId: 'o1',
            title: 'Chat',
            readOnly: true,
            testState: ChatState(error: 'rate_limited'))));
    expect(find.text('rate_limited'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('pagination does not retrigger while already loading',
      (tester) async {
    var calls = 0;
    final messages =
        List.generate(30, (i) => msg('$i', 'driver', 'Message $i'));
    await tester.pumpWidget(MaterialApp(
        home: ChatScreen(
            orderId: 'o1',
            title: 'Chat',
            testState: ChatState(
                messages: messages, nextBeforeId: 'older', loadingMore: true),
            onTestLoadMore: () => calls++)));
    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await tester.pump();
    expect(calls, 0);
  });

  testWidgets('audit demo cannot enable the production composer',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: ChatScreen(
            orderId: 'audit',
            title: 'Chat',
            auditDemo: true,
            testState: ChatState())));
    expect(find.byType(TextField), findsNothing);
  });
}
