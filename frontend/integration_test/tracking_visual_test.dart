import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tow_truck_frontend/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const captureState = String.fromEnvironment(
    'EVIK_VISUAL_CAPTURE_STATE',
    defaultValue: 'close',
  );
  const holdCapture = bool.fromEnvironment('EVIK_VISUAL_CAPTURE_HOLD');

  Future<void> holdIf(String state) async {
    if (!holdCapture || captureState != state) return;
    // An explicit audit-only hold lets the host capture real simulator pixels.
    await Completer<void>().future;
  }

  testWidgets('audit tracking supports expanded sheet and manual close zoom',
      (tester) async {
    // IntegrationTest inherits flutter_test's HTTP override, which otherwise
    // replaces real map tile responses with synthetic failures. Device visual
    // QA must exercise the configured provider, not fake tiles.
    HttpOverrides.global = null;
    app.main();
    await tester.pump(const Duration(seconds: 8));

    expect(find.text('Водитель едет к вам'), findsOneWidget);
    // ignore: avoid_print
    print('CAPTURE_INITIAL');
    await holdIf('compact');
    await tester.drag(
      find.text('Водитель едет к вам'),
      const Offset(0, -650),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Детали заказа'), findsOneWidget);
    // The external simulator capture waits for this stable real-tile state.
    // ignore: avoid_print
    print('CAPTURE_EXPANDED');
    await holdIf('expanded');

    await tester.drag(
      find.text('Водитель едет к вам'),
      const Offset(0, 650),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.drag(
      find.text('Водитель едет к вам'),
      const Offset(0, 650),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Детали заказа'), findsNothing);
    final zoomIn = find.byIcon(Icons.add_rounded);
    expect(zoomIn, findsOneWidget);
    await tester.tap(zoomIn);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(zoomIn);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byTooltip('Вернуться к маршруту'), findsOneWidget);
    // ignore: avoid_print
    print('CAPTURE_CLOSE');
    await holdIf('close');
  });
}
