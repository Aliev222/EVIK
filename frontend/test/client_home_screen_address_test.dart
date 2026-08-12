import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tow_truck_frontend/features/client/presentation/providers/order_flow_provider.dart';
import 'package:tow_truck_frontend/features/client/presentation/screens/client_home_screen.dart';
import 'package:tow_truck_frontend/features/map/domain/entities/map_location.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order_flow_state.dart';

class _StubOrderFlowNotifier extends OrderFlowNotifier {
  // ignore: use_super_parameters
  _StubOrderFlowNotifier(Ref ref, OrderFlowState initialState) : super(ref) {
    state = initialState;
  }

  @override
  Future<void> restoreActiveFlow() async {}

  @override
  Future<void> detectCurrentLocation() async {}
}

Widget _buildHome(OrderFlowState state) {
  return ProviderScope(
    overrides: [
      orderFlowProvider
          .overrideWith((ref) => _StubOrderFlowNotifier(ref, state)),
    ],
    child: const MaterialApp(home: ClientHomeScreen()),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home address card shows the resolved pickup address',
      (tester) async {
    await tester.pumpWidget(_buildHome(const OrderFlowState(
      pickupLocation: MapLocation(
        latitude: 42.9849,
        longitude: 47.4947,
        address: 'ул. Пушкина, 1, Махачкала',
      ),
    )));

    await tester.pump();
    await tester.pump();

    expect(find.text('ул. Пушкина, 1, Махачкала'), findsOneWidget);

    // Tear down the widget tree so in-flight location work never leaks.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('home address card shows "Определяем адрес…" while loading',
      (tester) async {
    await tester.pumpWidget(_buildHome(const OrderFlowState(isLoading: true)));

    await tester.pump();
    await tester.pump();

    expect(find.text('Определяем адрес…'), findsOneWidget);

    // The loading indicator animates indefinitely, so do not pumpAndSettle;
    // unmount the tree instead to let the state settle.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}