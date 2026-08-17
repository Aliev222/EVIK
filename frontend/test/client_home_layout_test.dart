import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tow_truck_frontend/core/network/connectivity_provider.dart';
import 'package:tow_truck_frontend/core/realtime/websocket_client.dart';
import 'package:tow_truck_frontend/core/services/location_service.dart';
import 'package:tow_truck_frontend/features/client/presentation/providers/order_flow_provider.dart';
import 'package:tow_truck_frontend/features/client/presentation/screens/client_app_shell.dart';
import 'package:tow_truck_frontend/features/client/presentation/screens/client_home_screen.dart';
import 'package:tow_truck_frontend/features/client/presentation/widgets/client_bottom_nav.dart';
import 'package:tow_truck_frontend/features/map/domain/entities/map_location.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order_flow_state.dart';
import 'package:tow_truck_frontend/features/order/presentation/providers/order_provider.dart';

/// Deterministic geolocator platform: no method channels, no timers, so the
/// home screen's location flow resolves synchronously inside widget tests.
class _FakeGeolocatorPlatform extends GeolocatorPlatform {
  _FakeGeolocatorPlatform({this.lastKnown, this.current});

  final Position? lastKnown;
  final Position? current;

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

/// Reverse geocoding that never completes — simulates a backend that is
/// unreachable without an HTTP error (a request "hanging" until timeout).
class _HangingLocationService implements LocationService {
  final Completer<String?> _never = Completer<String?>();

  @override
  Future<String?> reverseGeocode({required double lat, required double lng}) =>
      _never.future;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
        '${invocation.memberName} must not be used in this test');
  }
}

class _StubOrderFlowNotifier extends OrderFlowNotifier {
  // ignore: use_super_parameters
  _StubOrderFlowNotifier(Ref ref, OrderFlowState initialState) : super(ref) {
    state = initialState;
  }

  @override
  Future<void> restoreActiveFlow() async {}

  @override
  Future<void> detectCurrentLocation({double? lat, double? lng}) async {}
}

/// Real ClientAppShell composition (extendBody Scaffold + ClientBottomNav)
/// with a resolved address, wired up for widget tests.
Widget _buildShell(double bottomPadding) {
  return ProviderScope(
    overrides: [
      connectivityProvider.overrideWith((ref) => Stream.value(true)),
      webSocketStatusProvider.overrideWith(
        (ref) => Stream.value(WebSocketConnectionStatus.connected),
      ),
      orderFlowProvider.overrideWith(
        (ref) => _StubOrderFlowNotifier(
          ref,
          const OrderFlowState(
            pickupLocation: MapLocation(
              latitude: 42.9849,
              longitude: 47.4947,
              address: 'ул. Пушкина, 1, Махачкала',
            ),
          ),
        ),
      ),
    ],
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(padding: EdgeInsets.only(bottom: bottomPadding)),
        child: const ClientAppShell(),
      ),
    ),
  );
}

/// Home screen with the REAL order flow notifier and a hanging reverse
/// geocoder — the address card must leave the eternal loading state.
Widget _buildHomeWithRealFlow({LocationService? locationService}) {
  return ProviderScope(
    overrides: [
      orderFlowProvider.overrideWith((ref) => OrderFlowNotifier(ref)),
      if (locationService != null)
        locationServiceProvider.overrideWithValue(locationService),
    ],
    child: const MaterialApp(home: ClientHomeScreen()),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    GeolocatorPlatform.instance = _FakeGeolocatorPlatform(
      lastKnown: _testPosition,
      current: _testPosition,
    );
    SharedPreferences.setMockInitialValues({});
  });

  group('services card vs bottom nav gap', () {
    for (final inset in [0.0, 34.0]) {
      testWidgets('~15px gap between card bottom and navbar top '
          '(padding.bottom=$inset)', (tester) async {
        tester.view.physicalSize = const Size(1170, 2532);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_buildShell(inset));
        await tester.pump();
        await tester.pump();

        final cardRect = tester.getRect(
          find.byKey(const ValueKey('client_services_card')),
        );
        final navRect = tester.getRect(find.byType(ClientBottomNav));
        final gap = navRect.top - cardRect.bottom;

        // The gap is the `_servicesCardBottomGap` constant exactly; the body
        // extends behind the navbar under extendBody, so no inset arithmetic
        // is involved (verified for insets 0 and 34).
        expect(gap, closeTo(15, 3));

        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      });
    }

    testWidgets('my location button and attribution stay above the card',
        (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_buildShell(34));
      await tester.pump();
      await tester.pump();

      final cardRect = tester.getRect(
        find.byKey(const ValueKey('client_services_card')),
      );
      final buttonRect = tester.getRect(
        find.byTooltip('Моё местоположение'),
      );
      final attributionRect = tester.getRect(
        find.text('© OpenStreetMap contributors'),
      );

      // Button bottom sits 12px above the card top (unchanged relative gap).
      expect(buttonRect.bottom, closeTo(cardRect.top - 12, 3));
      // Attribution stays 56px above the button bottom, clear of the card.
      expect(attributionRect.bottom, closeTo(buttonRect.bottom - 56, 3));
      expect(attributionRect.bottom, lessThan(cardRect.top));

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });

  group('address detection timeout', () {
    testWidgets(
        'hanging reverseGeocode falls to "Не удалось определить адрес" '
        'with retry, coordinates stay visible', (tester) async {
      await tester.pumpWidget(
        _buildHomeWithRealFlow(locationService: _HangingLocationService()),
      );
      await tester.pump();
      await tester.pump();

      // While the backend hangs, the card must show the loading state with
      // the last-known coordinates already visible.
      expect(find.text('Определяем адрес…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('42.98490, 47.49470'), findsOneWidget);

      // Backend unreachable: the request hangs. Advance fake time past the
      // hard 12s cap — the flow must time out, not spin forever.
      await tester.pump(const Duration(seconds: 13));
      await tester.pump();

      expect(find.text('Не удалось определить адрес'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
      expect(find.text('42.98490, 47.49470'), findsOneWidget);

      // Retry restarts the detection (loading again), and times out again.
      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await tester.pump();
      await tester.pump();
      expect(find.text('Определяем адрес…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pump(const Duration(seconds: 13));
      await tester.pump();
      expect(find.text('Не удалось определить адрес'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('reverseGeocode throwing an error also falls to fail state',
        (tester) async {
      await tester.pumpWidget(_buildHomeWithRealFlow(
        locationService: _ThrowingLocationService(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(find.text('Не удалось определить адрес'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
      expect(find.text('42.98490, 47.49470'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}

class _ThrowingLocationService implements LocationService {
  @override
  Future<String?> reverseGeocode({required double lat, required double lng}) {
    return Future.error(StateError('backend unreachable'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
        '${invocation.memberName} must not be used in this test');
  }
}