import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tow_truck_frontend/core/services/realtime_location_service.dart';
import 'package:tow_truck_frontend/features/client/presentation/providers/real_time_driver_provider.dart';
import 'package:tow_truck_frontend/features/map/presentation/widgets/animated_driver_marker.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';

/// In-memory real-time service so tests can inject DriverLocationUpdate
/// events without opening a real WebSocket connection.
class FakeRealTimeLocationService extends RealTimeLocationService {
  final StreamController<DriverLocationUpdate> _driverCtrl =
      StreamController<DriverLocationUpdate>.broadcast();
  final StreamController<OrderUpdate> _orderCtrl =
      StreamController<OrderUpdate>.broadcast();
  final StreamController<String> _connCtrl =
      StreamController<String>.broadcast();
  final List<String> connectCalls = <String>[];

  @override
  Stream<DriverLocationUpdate> get driverLocationStream =>
      _driverCtrl.stream;

  @override
  Stream<OrderUpdate> get orderUpdateStream => _orderCtrl.stream;

  @override
  Stream<String> get connectionStream => _connCtrl.stream;

  @override
  Future<bool> connect({
    required String userId,
    required String userType,
    String accessToken = '',
  }) async {
    connectCalls.add('$userId|$userType|$accessToken');
    return true;
  }

  @override
  Future<void> disconnect() async {}

  @override
  void dispose() {
    _driverCtrl.close();
    _orderCtrl.close();
    _connCtrl.close();
  }

  void emitDriverLocation(DriverLocationUpdate update) {
    _driverCtrl.add(update);
  }
}

/// Minimal harness mirroring tracking_screen's behavior: it renders the driver
/// marker only once a driver location is available.
class _MarkerHarness extends ConsumerWidget {
  const _MarkerHarness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(realTimeDriverProvider).driverLocation;
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text(
            location == null
                ? 'marker: none'
                : 'marker: ${location.lat}',
            key: const Key('driverMarker'),
          ),
        ),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('marker renders on the FIRST DriverLocationUpdate', (
    tester,
  ) async {
    final fakeService = FakeRealTimeLocationService();
    final container = ProviderContainer(
      overrides: [
        realTimeLocationServiceProvider.overrideWithValue(fakeService),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const _MarkerHarness()),
    );

    expect(find.text('marker: none'), findsOneWidget);

    await container
        .read(realTimeDriverProvider.notifier)
        .startTracking(
          'order-1',
          const LocationModel(
            lat: 55.0,
            lng: 37.0,
            address: 'pickup',
          ),
          userId: 'client-1',
          accessToken: 'token-1',
        );

    // No route / bearing are required for the marker to appear.
    fakeService.emitDriverLocation(
      DriverLocationUpdate(
        driverId: 'driver-1',
        lat: 55.7558,
        lng: 37.6173,
        bearing: 0,
        speed: 0,
        status: DriverMarkerStatus.toPickup,
        orderId: 'order-1',
        timestamp: DateTime.now(),
      ),
    );
    await tester.pump();

    expect(find.text('marker: 55.7558'), findsOneWidget);
    expect(find.text('marker: none'), findsNothing);
  });

  testWidgets('marker keeps the last known position while updates pause', (
    tester,
  ) async {
    final fakeService = FakeRealTimeLocationService();
    final container = ProviderContainer(
      overrides: [
        realTimeLocationServiceProvider.overrideWithValue(fakeService),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const _MarkerHarness()),
    );

    await container
        .read(realTimeDriverProvider.notifier)
        .startTracking(
          'order-1',
          const LocationModel(
            lat: 55.0,
            lng: 37.0,
            address: 'pickup',
          ),
          userId: 'client-1',
          accessToken: 't',
        );

    fakeService.emitDriverLocation(
      DriverLocationUpdate(
        driverId: 'driver-1',
        lat: 55.7,
        lng: 37.6,
        bearing: 0,
        speed: 0,
        status: DriverMarkerStatus.toPickup,
        orderId: 'order-1',
        timestamp: DateTime.now(),
      ),
    );
    await tester.pump();
    expect(find.text('marker: 55.7'), findsOneWidget);

    // No further events arrive — the marker must not vanish.
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('marker: 55.7'), findsOneWidget);
  });

  test('client WS connects with the real user id and access token', () async {
    final fakeService = FakeRealTimeLocationService();
    final container = ProviderContainer(
      overrides: [
        realTimeLocationServiceProvider.overrideWithValue(fakeService),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(realTimeDriverProvider.notifier)
        .startTracking(
          'order-1',
          const LocationModel(lat: 55.0, lng: 37.0, address: 'pickup'),
          userId: 'client-77',
          accessToken: 'abc',
        );

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(fakeService.connectCalls.length, 1);
    expect(fakeService.connectCalls.first, 'client-77|client|abc');
  });
}