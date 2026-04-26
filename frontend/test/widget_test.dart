import 'package:evik_frontend/features/onboarding/presentation/screens/role_selection_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('RoleSelectionScreen renders for unauthenticated flow',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: RoleSelectionScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(RoleSelectionScreen), findsOneWidget);
  });
}
