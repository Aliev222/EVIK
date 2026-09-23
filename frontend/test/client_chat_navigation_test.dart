import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tow_truck_frontend/features/chat/presentation/chat_controller.dart';
import 'package:tow_truck_frontend/features/chat/presentation/chat_screen.dart';

void main() {
  testWidgets('client active chat route has production composer',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: ChatScreen(
            orderId: 'o1', title: 'Водитель', testState: ChatState())));
    expect(find.byType(TextField), findsOneWidget);
  });
  testWidgets('client completed chat route is read-only history',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: ChatScreen(
            orderId: 'o1',
            title: 'Водитель',
            readOnly: true,
            testState: ChatState())));
    expect(find.byType(TextField), findsNothing);
    expect(
        find.text('Чат закрыт для отправки новых сообщений'), findsOneWidget);
  });

  testWidgets('client cancelled chat route is read-only history',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: ChatScreen(
            orderId: 'o1',
            title: 'Водитель',
            readOnly: true,
            testState: ChatState())));
    expect(find.byType(TextField), findsNothing);
    expect(
        find.text('Чат закрыт для отправки новых сообщений'), findsOneWidget);
  });
}
