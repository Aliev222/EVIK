import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:tow_truck_frontend/features/client/presentation/screens/edit_order_route_screen.dart';
import 'package:tow_truck_frontend/features/development/ui_audit_fixtures.dart';
import 'package:tow_truck_frontend/features/client/presentation/screens/pickup_location_screen.dart';
import 'package:google_fonts/src/google_fonts_base.dart' as google_fonts_base;

import 'package:tow_truck_frontend/core/network/connectivity_provider.dart';
import 'package:tow_truck_frontend/core/realtime/websocket_client.dart';
import 'package:tow_truck_frontend/features/auth/domain/entities/user.dart';
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'package:tow_truck_frontend/features/client/presentation/providers/order_flow_provider.dart';
import 'package:tow_truck_frontend/features/client/presentation/screens/client_app_shell.dart';
import 'package:tow_truck_frontend/features/client/presentation/screens/vehicle_selection_screen.dart';
import 'package:tow_truck_frontend/features/client/presentation/widgets/services_placeholder_screen.dart';
import 'package:tow_truck_frontend/features/driver/data/repository/driver_verification_repository.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/available_orders_provider.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/driver_moderation_provider.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/driver_provider.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/driver_status_provider.dart';
import 'package:tow_truck_frontend/features/driver/presentation/screens/driver_main_screen.dart';
import 'package:tow_truck_frontend/features/map/domain/entities/map_location.dart';
import 'package:tow_truck_frontend/features/map/presentation/providers/map_provider.dart';
import 'package:tow_truck_frontend/features/onboarding/presentation/screens/role_selection_screen.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order_flow_state.dart';
import 'package:tow_truck_frontend/features/order/presentation/providers/order_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    _installPluginMocks();
  });

  tearDownAll(() {
    GoogleFonts.config.allowRuntimeFetching = true;
    _clearPluginMocks();
  });

  setUp(() {
    GeolocatorPlatform.instance = _FakeGeolocatorPlatform();
  });

  testWidgets('back from replacement pickup route never pops the last page',
      (tester) async {
    await _setIphone17ProSize(tester);
    await tester.runAsync(() async {
      await GoogleFonts.pendingFonts([
        for (final weight in [
          FontWeight.w400,
          FontWeight.w500,
          FontWeight.w600,
          FontWeight.w700,
          FontWeight.w800
        ])
          GoogleFonts.inter(fontWeight: weight),
      ]);
    });
    final router = GoRouter(
      initialLocation: '/order/search',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const Text('Home fallback')),
        GoRoute(
            path: '/ui-audit',
            builder: (_, __) => const Text('Audit fallback')),
        GoRoute(
            path: '/order/search', builder: (_, __) => const Text('Search')),
        GoRoute(
            path: '/order/pickup',
            builder: (_, __) => const PickupLocationScreen()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        mapProvider.overrideWith((ref) => _TestMapNotifier()),
        orderFlowProvider.overrideWith((ref) => _StubOrderFlowNotifier(ref)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    router.go('/order/pickup');
    await _settleWithFonts(tester);
    expect(router.canPop(), isFalse);
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('fallback'), findsOneWidget);
  });

  for (final status in [OrderStatus.onWay, OrderStatus.evacuating]) {
    testWidgets('route editor back preserves active order: ${status.name}',
        (tester) async {
      await _setIphone17ProSize(tester);
      await tester.runAsync(() => GoogleFonts.pendingFonts([
            for (final weight in [
              FontWeight.w400,
              FontWeight.w500,
              FontWeight.w600,
              FontWeight.w700,
              FontWeight.w800
            ])
              GoogleFonts.inter(fontWeight: weight),
          ]));
      final container = ProviderContainer(overrides: uiAuditOverrides());
      addTearDown(container.dispose);
      final original = container.read(orderFlowProvider).activeOrder!;
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: Builder(
                builder: (ctx) => Scaffold(
                        body: TextButton(
                      onPressed: () => editOrderRoute(
                          ctx, original.copyWith(status: status)),
                      child: const Text('Ожидание: сменить адрес'),
                    )))),
      ));
      await tester.tap(find.text('Ожидание: сменить адрес'));
      await tester.pumpAndSettle();
      if (status != OrderStatus.evacuating) {
        expect(find.text('Откуда забрать автомобиль?'), findsOneWidget);
        await tester.tap(find.text('Далее — куда отвезти'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Куда отвезти автомобиль?'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      if (status != OrderStatus.evacuating) {
        expect(find.text('Откуда забрать автомобиль?'), findsOneWidget);
        await tester.tap(find.byIcon(Icons.arrow_back_rounded));
        await tester.pumpAndSettle();
      }
      expect(find.text('Ожидание: сменить адрес'), findsOneWidget);
      expect(container.read(orderFlowProvider).activeOrder, same(original));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'route editor confirm before pickup returns to active order screen',
      (tester) async {
    await _setIphone17ProSize(tester);
    await tester.runAsync(() => GoogleFonts.pendingFonts([
          for (final weight in [
            FontWeight.w400,
            FontWeight.w500,
            FontWeight.w600,
            FontWeight.w700,
            FontWeight.w800
          ])
            GoogleFonts.inter(fontWeight: weight),
        ]));
    final container = ProviderContainer(overrides: uiAuditOverrides());
    addTearDown(container.dispose);
    final original = container.read(orderFlowProvider).activeOrder!;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          home: Builder(
              builder: (ctx) => Scaffold(
                    body: Column(
                      children: [
                        const Text('Экран текущего заказа'),
                        TextButton(
                          onPressed: () => editOrderRoute(ctx,
                              original.copyWith(status: OrderStatus.onWay)),
                          child: const Text('Сменить адрес до погрузки'),
                        ),
                      ],
                    ),
                  ))),
    ));
    await tester.tap(find.text('Сменить адрес до погрузки'));
    await tester.pumpAndSettle();
    expect(find.text('Откуда забрать автомобиль?'), findsOneWidget);
    await tester.tap(find.text('Далее — куда отвезти'));
    await tester.pumpAndSettle();
    expect(find.text('Куда отвезти автомобиль?'), findsOneWidget);
    await tester.tap(find.text('Рассчитать новую стоимость'));
    await tester.pumpAndSettle();
    expect(find.text('Подтвердить маршрут'), findsOneWidget);
    await tester.tap(find.text('Подтвердить'));
    await tester.pumpAndSettle();
    expect(find.text('Экран текущего заказа'), findsOneWidget);
    expect(find.text('Откуда забрать автомобиль?'), findsNothing);
    expect(find.text('Куда отвезти автомобиль?'), findsNothing);
    expect(
        container.read(orderFlowProvider).activeOrder, isNot(same(original)));
    expect(tester.takeException(), isNull);
  }, skip: !const bool.fromEnvironment('EVIK_UI_AUDIT'));

  testWidgets('capture onboarding role selection', (tester) async {
    await _setIphone17ProSize(tester);
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: RoleSelectionScreen(),
        ),
      ),
    );

    await _settleWithFonts(tester);
    await expectLater(
      find.byType(RoleSelectionScreen),
      matchesGoldenFile('goldens/audit_role_selection_screen.png'),
    );
  });

  testWidgets('capture client home', (tester) async {
    await _setIphone17ProSize(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(_clientUser),
          connectivityProvider.overrideWith((ref) => Stream.value(true)),
          webSocketStatusProvider.overrideWith(
            (ref) => Stream.value(WebSocketConnectionStatus.connected),
          ),
          mapProvider.overrideWith((ref) => _TestMapNotifier()),
          orderFlowProvider.overrideWith((ref) => _StubOrderFlowNotifier(ref)),
        ],
        child: const MaterialApp(
          debugShowCheckedModeBanner: false,
          home: ClientAppShell(),
        ),
      ),
    );

    await _settleWithFonts(tester);
    await expectLater(
      find.byType(ClientAppShell),
      matchesGoldenFile('goldens/audit_client_home_screen.png'),
    );
  });

  testWidgets('capture services placeholder', (tester) async {
    await _setIphone17ProSize(tester);
    await tester.pumpWidget(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ServicesPlaceholderScreen(),
      ),
    );

    await _settleWithFonts(tester);
    await expectLater(
      find.byType(ServicesPlaceholderScreen),
      matchesGoldenFile('goldens/audit_services_placeholder_screen.png'),
    );
  });

  testWidgets('vehicle selection fits loading price cards on iPhone 17 Pro',
      (tester) async {
    await _setIphone17ProSize(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderFlowProvider.overrideWith(
            (ref) => _VehicleSelectionOrderFlowNotifier(ref),
          ),
        ],
        child: const MaterialApp(
          debugShowCheckedModeBanner: false,
          home: VehicleSelectionScreen(),
        ),
      ),
    );

    await _settleWithFonts(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('capture driver home', (tester) async {
    await _setIphone17ProSize(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(_driverUser),
          watchDriverModerationProvider.overrideWith(
            (ref, userId) => Stream<DriverVerificationDocument?>.value(null),
          ),
          watchDriverProvider.overrideWith(
            (ref, userId) => Stream<Driver?>.value(_driver),
          ),
          driverVerificationRepositoryProvider.overrideWithValue(
            const _FakeDriverVerificationRepository(),
          ),
          driverHomeStatusProvider.overrideWith(
            (ref) => const DriverStatusState(),
          ),
          driverStatusControllerProvider.overrideWith(
            (ref) => const _NoopDriverStatusController(),
          ),
          driverHomeAvailableOrdersProvider.overrideWith(
            (ref) => const AsyncValue.data(<Order>[]),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: DriverMainScreen(auditNow: DateTime(2026, 9, 16, 9)),
        ),
      ),
    );

    await _settleWithFonts(tester);
    await expectLater(
      find.byType(DriverMainScreen),
      matchesGoldenFile('goldens/audit_driver_home_screen.png'),
    );
  });
}

void _installPluginMocks() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async {
      final cacheDir = Directory.systemTemp.createTempSync('avro-map-cache-');
      switch (call.method) {
        case 'getApplicationCacheDirectory':
        case 'getTemporaryDirectory':
          return cacheDir.path;
        default:
          return null;
      }
    },
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async {
      switch (call.method) {
        case 'read':
          return null;
        case 'readAll':
          return <String, String>{};
        case 'containsKey':
          return false;
        case 'write':
        case 'delete':
        case 'deleteAll':
          return null;
        default:
          return null;
      }
    },
  );
}

void _clearPluginMocks() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    null,
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    null,
  );
}

class _FakeGeolocatorPlatform extends GeolocatorPlatform {
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
      _testPosition;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async =>
      _testPosition;

  @override
  Stream<Position> getPositionStream({
    LocationSettings? locationSettings,
  }) =>
      Stream<Position>.value(_testPosition);
}

Future<void> _setIphone17ProSize(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1206, 2622);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

Future<void> _settleWithFonts(WidgetTester tester) async {
  await tester.pump();
  if (google_fonts_base.pendingFontFutures.isNotEmpty) {
    await Future.wait(google_fonts_base.pendingFontFutures);
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

final User _clientUser = User(
  id: 'client',
  phone: '+79990000000',
  fullName: 'Client',
  role: UserRole.client,
  isActive: true,
  createdAt: DateTime(2026, 4, 24),
  lastSeen: DateTime(2026, 4, 24),
);

final User _driverUser = User(
  id: 'driver',
  phone: '+79990000000',
  fullName: 'Driver',
  role: UserRole.driver,
  isActive: true,
  createdAt: DateTime(2026, 4, 24),
  lastSeen: DateTime(2026, 4, 24),
);

const Driver _driver = Driver(
  userId: 'driver',
  vehicleModel: 'Ford Transit',
  vehicleNumber: 'А111АА77',
  vehicleType: VehicleType.light,
  rating: 4.9,
  totalOrders: 50,
  isOnline: false,
  currentLocation: DriverLocation(lat: 42.9849, lng: 47.5047),
  isVerified: true,
  earnings: DriverEarnings(today: 0, week: 0, month: 0),
);

final Position _testPosition = Position(
  latitude: 42.9849,
  longitude: 47.5047,
  timestamp: DateTime(2026, 1, 1),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

class _TestMapNotifier extends MapNotifier {
  @override
  Future<void> getCurrentLocation() async {
    state = state.copyWith(
      currentPosition: const MapLocation(
        latitude: 42.9849,
        longitude: 47.5047,
        address: 'ул. Пушкина, 1, Махачкала',
      ),
      cameraPosition: const MapLocation(
        latitude: 42.9849,
        longitude: 47.5047,
        address: 'ул. Пушкина, 1, Махачкала',
      ),
      permissionGranted: true,
      isLoading: false,
      error: null,
    );
  }
}

class _StubOrderFlowNotifier extends OrderFlowNotifier {
  // ignore: use_super_parameters
  _StubOrderFlowNotifier(Ref ref) : super(ref) {
    state = const OrderFlowState(
      pickupLocation: MapLocation(
        latitude: 42.9849,
        longitude: 47.5047,
        address: 'ул. Пушкина, 1, Махачкала',
      ),
    );
  }

  @override
  Future<void> restoreActiveFlow() async {}

  @override
  Future<void> detectCurrentLocation({double? lat, double? lng}) async {}
}

class _VehicleSelectionOrderFlowNotifier extends OrderFlowNotifier {
  // ignore: use_super_parameters
  _VehicleSelectionOrderFlowNotifier(Ref ref) : super(ref) {
    state = const OrderFlowState(
      currentStep: OrderFlowStep.vehicleSelection,
      pickupLocation: MapLocation(
        latitude: 42.9849,
        longitude: 47.5047,
        address: 'проспект Расула Гамзатова, 12, Махачкала',
      ),
      destinationLocation: MapLocation(
        latitude: 42.9662,
        longitude: 47.5126,
        address: 'улица Петра I, 97, Махачкала',
      ),
      selectedVehicleType: VehicleType.light,
      selectedTowTruckType: TowTruckType.winch,
      blockedWheelsCount: 2,
      isPriceLoading: true,
    );
  }

  @override
  Future<void> restoreActiveFlow() async {}

  @override
  Future<void> detectCurrentLocation({double? lat, double? lng}) async {}
}

class _NoopDriverStatusController implements DriverStatusController {
  const _NoopDriverStatusController();

  @override
  Future<void> acceptOrder(String orderId) async {}

  @override
  Future<void> cancelOrder(String orderId, String reason) async {}

  @override
  Future<void> toggleOnlineStatus() async {}

  @override
  Future<void> updateLocation(double lat, double lng) async {}

  @override
  Future<void> updateOrderStatus(OrderStatus status) async {}
}

class _FakeDriverVerificationRepository
    implements DriverVerificationRepository {
  const _FakeDriverVerificationRepository();

  @override
  Future<DriverVerificationResult> submitVerification({
    required DriverVerificationPayload payload,
    void Function(double progress, String message)? onProgress,
  }) async {
    return DriverVerificationResult(
      documentUrls: const <String, String>{},
      submittedAt: DateTime(2026, 4, 24),
    );
  }
}
