import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tow_truck_frontend/shared/widgets/skeleton_card.dart';

void main() {
  testWidgets('fits the compact history loading card without overflow',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 336,
            height: 82,
            child: SkeletonCard(height: 82),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
