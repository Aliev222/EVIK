import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evik_frontend/main.dart';

void main() {
  testWidgets('Initial EVIK flow renders', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: EvikApp(),
      ),
    );

    expect(find.byKey(const ValueKey<String>('launch-splash')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('home-screen')), findsOneWidget);
    expect(find.text('Выберите роль'), findsOneWidget);
  });
}
