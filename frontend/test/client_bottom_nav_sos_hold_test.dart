import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tow_truck_frontend/features/client/presentation/widgets/client_bottom_nav.dart';

Widget _buildNav(VoidCallback? onActivated) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: ClientBottomNav(
          activeTab: ClientTab.home,
          onTabChanged: (_) {},
          onSosActivated: onActivated,
        ),
      ),
    ),
  );
}

/// Returns the progress ring painter used by the SOS button, or null when
/// the ring is not part of the current frame.
double? _ringProgress(WidgetTester tester) {
  for (final paint in tester.widgetList<CustomPaint>(find.byType(CustomPaint))) {
    final painter = paint.painter;
    if (painter != null &&
        painter.runtimeType.toString() == '_HoldRingPainter') {
      return (painter as dynamic).progress as double;
    }
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Finder sosIcon() => find.byIcon(Icons.phone_in_talk_rounded);

  testWidgets('holding SOS for ~3s activates it exactly once', (tester) async {
    var activated = 0;
    await tester.pumpWidget(_buildNav(() => activated++));

    final gesture = await tester.startGesture(tester.getCenter(sosIcon()));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // Ring is visible and already filling during the hold.
    expect(_ringProgress(tester), isNotNull);
    expect(_ringProgress(tester)!, greaterThan(0));

    await tester.pump(const Duration(seconds: 4));
    expect(activated, 1);

    await gesture.up();
    await tester.pump();
    expect(activated, 1);

    // Flush the internal post-activation reset timer before teardown.
    await tester.pump(const Duration(milliseconds: 300));
    expect(activated, 1);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('quick tap (<1s) does not activate SOS', (tester) async {
    var activated = 0;
    await tester.pumpWidget(_buildNav(() => activated++));

    final gesture = await tester.startGesture(tester.getCenter(sosIcon()));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pump();

    expect(activated, 0);

    // Ring is reset after the cancelled tap.
    expect(_ringProgress(tester), 0);

    // It must never fire later even after the full hold window elapses.
    await tester.pump(const Duration(seconds: 4));
    expect(activated, 0);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('releasing mid-hold (~1.5s) cancels without activating',
      (tester) async {
    var activated = 0;
    await tester.pumpWidget(_buildNav(() => activated++));

    final gesture = await tester.startGesture(tester.getCenter(sosIcon()));
    await tester.pump(const Duration(milliseconds: 1500));
    await gesture.up();
    await tester.pump();

    expect(activated, 0);
    expect(_ringProgress(tester), 0);

    // No late activation even after the full hold window has passed.
    await tester.pump(const Duration(seconds: 4));
    expect(activated, 0);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('micro finger movement during the hold does not cancel it',
      (tester) async {
    var activated = 0;
    await tester.pumpWidget(_buildNav(() => activated++));

    final gesture = await tester.startGesture(tester.getCenter(sosIcon()));
    await tester.pump(const Duration(milliseconds: 100));

    // Move beyond the default touch slop (18px). A tap recognizer would
    // cancel here; the raw Listener must keep the hold running.
    await gesture.moveBy(const Offset(30, -15));
    await tester.pump(const Duration(seconds: 4));
    expect(activated, 1);

    await gesture.up();
    await tester.pump();
    expect(activated, 1);

    // Flush the internal post-activation reset timer before teardown.
    await tester.pump(const Duration(milliseconds: 300));
    expect(activated, 1);

    await tester.pumpWidget(const SizedBox());
  });
}