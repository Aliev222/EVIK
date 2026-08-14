import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tow_truck_frontend/features/driver/presentation/screens/driver_blocked_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap({String? reason}) {
    return ProviderScope(
      child: MaterialApp(
        home: DriverBlockedScreen(reason: reason),
      ),
    );
  }

  testWidgets('blocked screen offers support but no resubmission',
      (tester) async {
    await tester.pumpWidget(wrap());

    expect(find.text('Аккаунт заблокирован'), findsOneWidget);
    expect(find.text('Обратиться в поддержку'), findsOneWidget);
    expect(
      find.text('Исправить и переотправить документы'),
      findsNothing,
      reason: 'заблокированному водителю нельзя давать путь к переподаче',
    );
  });

  testWidgets('blocked screen shows the moderator reason', (tester) async {
    await tester.pumpWidget(wrap(reason: 'Мошенничество при верификации'));

    expect(find.text('Аккаунт заблокирован'), findsOneWidget);
    expect(find.text('Мошенничество при верификации'), findsOneWidget);
    expect(find.text('Обратиться в поддержку'), findsOneWidget);
  });
}
