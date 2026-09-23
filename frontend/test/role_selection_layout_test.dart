import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tow_truck_frontend/features/auth/domain/entities/user.dart';
import 'package:tow_truck_frontend/features/onboarding/presentation/screens/role_selection_screen.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDownAll(() => GoogleFonts.config.allowRuntimeFetching = true);

  for (final size in [const Size(402, 874), const Size(320, 568)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('role selection ${size.width} at text scale $scale',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const RoleSelectionScreen(),
          ),
        ));
        await tester.runAsync(() => GoogleFonts.pendingFonts());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Я водитель').hitTestable().first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final driverCta = find.text('Стать водителем');
        await tester.ensureVisible(driverCta);
        await tester.pumpAndSettle();
        await tester.tap(driverCta);
        expect(container.read(selectedOnboardingRoleProvider), UserRole.driver);
        await tester.ensureVisible(find.text('Заказать эвакуатор').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Заказать эвакуатор').hitTestable().first);
        await tester.pumpAndSettle();
        final clientCta = find.text('Вызвать эвакуатор');
        await tester.ensureVisible(clientCta);
        await tester.pumpAndSettle();
        await tester.tap(clientCta);
        expect(container.read(selectedOnboardingRoleProvider), UserRole.client);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
