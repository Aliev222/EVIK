import 'package:evik_frontend/features/onboarding/presentation/screens/role_selection_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture RoleSelectionScreen', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: RoleSelectionScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle(const Duration(milliseconds: 900));

    await expectLater(
      find.byType(RoleSelectionScreen),
      matchesGoldenFile('goldens/role_selection_screen.png'),
    );
  });
}
