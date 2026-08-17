import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:tow_truck_frontend/features/client/presentation/providers/order_flow_provider.dart';
import 'package:tow_truck_frontend/features/client/presentation/screens/client_home_screen.dart';
import 'package:tow_truck_frontend/features/client/presentation/screens/service_detail_screen.dart';
import 'package:tow_truck_frontend/features/client/presentation/widgets/osm_location_picker.dart';
import 'package:tow_truck_frontend/features/map/domain/entities/map_location.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order_flow_state.dart';

/// Deterministic geolocator platform: no method channels, no timers, so the
/// home screen's location flow resolves synchronously inside widget tests.
class _FakeGeolocatorPlatform extends GeolocatorPlatform {
  _FakeGeolocatorPlatform({this.lastKnown, this.current});

  final Position? lastKnown;
  final Position? current;
  int getCurrentPositionCalls = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.always;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.always;

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async =>
      lastKnown;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    getCurrentPositionCalls++;
    final pos = current;
    if (pos == null) {
      throw Exception('no position available');
    }
    return pos;
  }

  @override
  Stream<Position> getPositionStream({
    LocationSettings? locationSettings,
  }) =>
      const Stream<Position>.empty();
}

final Position _testPosition = Position(
  latitude: 42.9849,
  longitude: 47.4947,
  timestamp: DateTime(2026, 1, 1),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

class _StubOrderFlowNotifier extends OrderFlowNotifier {
  // ignore: use_super_parameters
  _StubOrderFlowNotifier(Ref ref, OrderFlowState initialState,
      {this.onDetect})
      : super(ref) {
    state = initialState;
  }

  final Future<void> Function(double lat, double lng)? onDetect;

  @override
  Future<void> restoreActiveFlow() async {}

  @override
  Future<void> detectCurrentLocation({double? lat, double? lng}) async {
    final callback = onDetect;
    if (callback != null && lat != null && lng != null) {
      await callback(lat, lng);
    }
  }
}

Widget _buildHome(
  OrderFlowState state, {
  Future<void> Function(double lat, double lng)? onDetect,
  VoidCallback? onProfilePressed,
}) {
  return ProviderScope(
    overrides: [
      orderFlowProvider.overrideWith(
        (ref) => _StubOrderFlowNotifier(ref, state, onDetect: onDetect),
      ),
    ],
    child: MaterialApp(
      home: ClientHomeScreen(onProfilePressed: onProfilePressed),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    GeolocatorPlatform.instance = _FakeGeolocatorPlatform(
      lastKnown: _testPosition,
      current: _testPosition,
    );
  });

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

  testWidgets('home address card shows failure text when detection fails',
      (tester) async {
    await tester.pumpWidget(_buildHome(
      const OrderFlowState(),
      onDetect: (lat, lng) async {
        // The reverse-geocode returned nothing: the flow leaves the pickup
        // location unresolved and surfaces the error state.
      },
    ));

    // With no pickup resolved, no isLoading, and a detection attempt already
    // fired, the card must reach the failure branch.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text('Не удалось определить адрес'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('tapping the address bar does not open the manual picker',
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

    await tester.tap(find.text('ул. Пушкина, 1, Махачкала'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(OsmLocationPicker), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('services card is present above the map', (tester) async {
    await tester.pumpWidget(_buildHome(const OrderFlowState(
      pickupLocation: MapLocation(
        latitude: 42.9849,
        longitude: 47.4947,
        address: 'ул. Пушкина, 1, Махачкала',
      ),
    )));

    await tester.pump();
    await tester.pump();

    expect(find.text('Услуги'), findsOneWidget);
    expect(find.text('Вызвать эвакуатор'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('fetches the position once and reverse-geocodes the same fix',
      (tester) async {
    GeolocatorPlatform.instance = _FakeGeolocatorPlatform(
      lastKnown: null,
      current: _testPosition,
    );

    final detected = <double>[];
    await tester.pumpWidget(_buildHome(
      const OrderFlowState(),
      onDetect: (lat, lng) async {
        detected.addAll([lat, lng]);
      },
    ));

    await tester.pump();
    await tester.pump();

    final fake = GeolocatorPlatform.instance as _FakeGeolocatorPlatform;
    expect(fake.getCurrentPositionCalls, 1);
    expect(detected.length, 2);
    expect(detected[0], closeTo(42.9849, 0.0001));
    expect(detected[1], closeTo(47.4947, 0.0001));

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('tapping the logo calls onProfilePressed', (tester) async {
    var profileOpened = false;
    await tester.pumpWidget(_buildHome(
      const OrderFlowState(),
      onProfilePressed: () => profileOpened = true,
    ));

    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('client_home_logo')));
    await tester.pump();

    expect(profileOpened, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('address bar shows coordinates once lat/lng are known',
      (tester) async {
    // While the address is still loading, the last-known fix must already be
    // rendered as coordinates under the "Определяем адрес…" line.
    await tester.pumpWidget(_buildHome(const OrderFlowState(isLoading: true)));

    await tester.pump();
    await tester.pump();

    expect(find.text('Определяем адрес…'), findsOneWidget);
    expect(find.text('42.98490, 47.49470'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('my location button is rendered on the map', (tester) async {
    await tester.pumpWidget(_buildHome(const OrderFlowState(
      pickupLocation: MapLocation(
        latitude: 42.9849,
        longitude: 47.4947,
        address: 'ул. Пушкина, 1, Махачкала',
      ),
    )));

    await tester.pump();
    await tester.pump();

    expect(find.byTooltip('Моё местоположение'), findsOneWidget);

    // Tapping recenters the camera on the known position (must not throw).
    await tester.tap(find.byTooltip('Моё местоположение'));
    await tester.pump();

    expect(find.byTooltip('Моё местоположение'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('tapping the map does not open anything', (tester) async {
    await tester.pumpWidget(_buildHome(const OrderFlowState(
      pickupLocation: MapLocation(
        latitude: 42.9849,
        longitude: 47.4947,
        address: 'ул. Пушкина, 1, Махачкала',
      ),
    )));

    await tester.pump();
    await tester.pump();

    // Free area of the map: left edge, away from header/address/services.
    await tester.tapAt(const Offset(40, 300));
    // flutter_map delays single-tap resolution by 250ms (double-tap
    // disambiguation); advance past it so no timer leaks.
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(OsmLocationPicker), findsNothing);
    expect(find.byType(ServiceDetailScreen), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}