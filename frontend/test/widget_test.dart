import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evik_frontend/main.dart';

void main() {
  testWidgets('Initial EVIK flow renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: EvikApp(),
      ),
    );

    expect(find.text('Evik'), findsOneWidget);
    expect(find.text('Выберите роль'), findsOneWidget);
  });
}
