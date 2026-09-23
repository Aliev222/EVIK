import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tow_truck_frontend/features/driver/presentation/widgets/active_order_card.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';

Order fixtureOrder() => Order(
      id: 'o1',
      clientId: 'client-1',
      status: OrderStatus.assigned,
      pickupLocation: const LocationModel(lat: 42, lng: 47, address: 'A'),
      dropoffLocation: const LocationModel(lat: 43, lng: 48, address: 'B'),
      vehicleType: VehicleType.light,
      distance: 1,
      estimatedPrice: 100,
      paymentMethod: PaymentMethod.cash,
      createdAt: DateTime.utc(2026),
    );

void main() {
  testWidgets('driver chat opens internal screen and call remains tel action',
      (tester) async {
    Uri? launched;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DriverActiveOrderCard(
              order: fixtureOrder(),
              driverLat: null,
              driverLng: null,
              onStatusUpdate: (_) async {},
              onCancel: () async {},
              onComplete: () async {},
              chatBuilder: (_) => const Scaffold(body: Text('Internal Chat')),
              launchUri: (uri) async => launched = uri,
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Чат'));
    await tester.pumpAndSettle();
    expect(find.text('Internal Chat'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Позвонить'));
    expect(launched?.scheme, 'tel');
    expect(find.text('SMS'), findsNothing);
  });
}
