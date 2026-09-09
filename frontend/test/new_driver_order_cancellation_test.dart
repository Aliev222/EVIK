import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tow_truck_frontend/core/network/api_client.dart';
import 'package:tow_truck_frontend/core/services/realtime_location_service.dart';
import 'package:tow_truck_frontend/core/storage/key_value_storage.dart';
import 'package:tow_truck_frontend/features/auth/domain/entities/user.dart';
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'package:tow_truck_frontend/features/driver/data/repository_impl/http_driver_repository.dart';
import 'package:tow_truck_frontend/features/driver/data/services/driver_notification_service.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver_stats.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver_work_state.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/driver_earnings_provider.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/driver_realtime_provider.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/new_driver_provider.dart';
import 'package:tow_truck_frontend/features/map/presentation/widgets/animated_driver_marker.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/features/order/presentation/providers/order_provider.dart';
import 'package:tow_truck_frontend/features/driver/data/services/driver_wake_service.dart';
import 'test_doubles/in_memory_order_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('payment event updates displayed payment method immediately', () async {
    final realtime = _FakeRealTimeLocationService();
    final container = _container(realtime);
    addTearDown(container.dispose);
    await container.read(newDriverProvider.notifier).initialized;
    realtime.emitOrderUpdate(OrderUpdate(
        orderId: 'order-1',
        status: OrderUpdateType.paymentMethodChanged,
        rawPayload: const {'payment_method': 'card'}));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(newDriverProvider).activeOrder?.paymentMethod,
        PaymentMethod.card);
  });

  test('HTTP refresh recovers cancellation and clears GPS order identity',
      () async {
    final realtime = _FakeRealTimeLocationService();
    final orders = _OrderSnapshotRepository();
    final container = _container(realtime, orders: orders);
    addTearDown(container.dispose);
    final notifier = container.read(newDriverProvider.notifier);
    await notifier.initialized;
    expect(container.read(driverRealTimeProvider).currentOrder, 'order-1');
    await notifier.resumeOnlineSession();
    expect(container.read(newDriverProvider).activeOrder, isNull);
    expect(container.read(newDriverProvider).workState, DriverWorkState.online);
    expect(container.read(driverRealTimeProvider).currentOrder, isNull);
  });

  test('failed refresh preserves active order and price', () async {
    final container = _container(_FakeRealTimeLocationService(),
        orders: _OrderSnapshotRepository()..failRequest = true);
    addTearDown(container.dispose);
    final notifier = container.read(newDriverProvider.notifier);
    await notifier.initialized;
    await notifier.resumeOnlineSession();
    expect(container.read(newDriverProvider).activeOrder?.id, 'order-1');
    expect(container.read(newDriverProvider).activeOrder?.price, 2500);
  });

  test('logout clears user and token, and a later wake cannot restore them',
      () async {
    final container = _container(_FakeRealTimeLocationService());
    addTearDown(container.dispose);
    await container.read(newDriverProvider.notifier).initialized;
    await container.read(authProvider.notifier).signOut();
    expect(container.read(authProvider).isAuthenticated, isFalse);
    expect(container.read(authProvider).accessToken, isNull);
    await container.read(driverWakeServiceProvider).ensureOnline();
    expect(container.read(authProvider).user, isNull);
  });

  test('cancelled event releases the active driver order back to online',
      () async {
    final realtime = _FakeRealTimeLocationService();
    final repo = _FakeDriverRepository();
    final container = ProviderContainer(
      overrides: [
        driverNotificationServiceProvider.overrideWithValue(
          _SilentDriverNotificationService(),
        ),
        authProvider.overrideWith((ref) => _FixedAuthNotifier(ref)),
        httpDriverRepositoryProvider.overrideWithValue(repo),
        realTimeLocationServiceProvider.overrideWithValue(realtime),
        driverRealTimeProvider.overrideWith(
          (ref) => _FakeDriverRealTimeNotifier(
              ref.read(realTimeLocationServiceProvider)),
        ),
        driverStatsFromEarningsProvider.overrideWithValue(DriverStats.mock),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(newDriverProvider.notifier);
    await _pumpUntil(
      () => container.read(newDriverProvider).activeOrder?.id == 'order-1',
    );

    expect(container.read(newDriverProvider).workState,
        DriverWorkState.hasActiveOrder);
    expect(container.read(newDriverProvider).activeOrder?.id, 'order-1');

    realtime.emitOrderUpdate(
      OrderUpdate(
        orderId: 'order-1',
        status: OrderUpdateType.orderCancelled,
        rawPayload: const <String, dynamic>{'reason': 'client_cancelled'},
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final state = container.read(newDriverProvider);
    expect(state.workState, DriverWorkState.online);
    expect(state.activeOrder, isNull);
    expect(state.availableOrders, isEmpty);
    expect(notifier.mounted, isTrue);
  });
}

ProviderContainer _container(_FakeRealTimeLocationService realtime,
        {_OrderSnapshotRepository? orders}) =>
    ProviderContainer(overrides: [
      driverNotificationServiceProvider.overrideWithValue(
        _SilentDriverNotificationService(),
      ),
      authProvider.overrideWith((ref) => _FixedAuthNotifier(ref)),
      httpDriverRepositoryProvider.overrideWithValue(_FakeDriverRepository()),
      realTimeLocationServiceProvider.overrideWithValue(realtime),
      driverRealTimeProvider
          .overrideWith((ref) => _FakeDriverRealTimeNotifier(realtime)),
      driverStatsFromEarningsProvider.overrideWithValue(DriverStats.mock),
      if (orders != null) orderRepositoryProvider.overrideWithValue(orders),
    ]);

class _SilentDriverNotificationService implements DriverNotificationService {
  @override
  Future<void> dispose() async {}

  @override
  Future<void> ensureInitialized() async {}

  @override
  Future<void> playAsset(String assetPath) async {}

  @override
  Future<void> playDriverArrived() async {}

  @override
  Future<void> playLongShift() async {}

  @override
  Future<void> playNewOrderSound() async {}

  @override
  Future<void> playOrderCancelled() async {}

  @override
  Future<void> playPaymentChanged({required bool isCash}) async {}

  @override
  Future<void> playShiftStarted() async {}

  @override
  Future<void> playTripStarted() async {}

  @override
  Future<void> scheduleLocationReminder() async {}

  @override
  Future<void> showOrderNotification(Order order) async {}

  @override
  Future<void> vibrateFeedback(DriverHapticType type) async {}
}

class _OrderSnapshotRepository extends InMemoryOrderRepository {
  bool failRequest = false;
  @override
  Future<Order?> getOrder(String orderId) async {
    if (failRequest) throw StateError('offline');
    return Order(
        id: orderId,
        clientId: 'client-1',
        driverId: 'driver-1',
        status: OrderStatus.cancelled,
        pickupLocation:
            const LocationModel(lat: 42.98, lng: 47.5, address: 'A'),
        dropoffLocation:
            const LocationModel(lat: 42.99, lng: 47.51, address: 'B'),
        vehicleType: VehicleType.light,
        distance: 10,
        estimatedPrice: 2500,
        paymentMethod: PaymentMethod.cash,
        createdAt: DateTime(2026));
  }
}

Future<void> _pumpUntil(bool Function() done) async {
  for (var i = 0; i < 30; i++) {
    if (done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('condition was not met in time');
}

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(Ref ref)
      : super(
          api: BackendAuthApi(apiClient: _NoopApiClient()),
          storage: InMemoryKeyValueStorage(),
          ref: ref,
        ) {
    state = AuthState(
      user: User(
        id: 'driver-1',
        phone: '+79990000000',
        fullName: 'Driver One',
        role: UserRole.driver,
        isActive: true,
        createdAt: DateTime(2026),
        lastSeen: DateTime(2026),
      ),
      accessToken: 'token-1',
      isRestoring: false,
    );
  }
}

class _FakeDriverRepository extends HttpDriverRepository {
  _FakeDriverRepository()
      : super(apiClient: _NoopApiClient(), accessToken: 'token-1');

  @override
  Future<Driver?> getDriver(String userId) async => const Driver(
        userId: 'driver-1',
        fullName: 'Driver One',
        phone: '+79990000000',
        vehicleModel: 'ГАЗель',
        vehicleNumber: 'А001АА05',
        vehicleType: VehicleType.light,
        rating: 5,
        totalOrders: 1,
        isOnline: true,
        isVerified: true,
        earnings: DriverEarnings(today: 0, week: 0, month: 0),
      );

  @override
  Future<Map<String, dynamic>> getActiveOrder(String driverId) async =>
      <String, dynamic>{
        'id': 'order-1',
        'user_id': 'client-1',
        'driver_id': 'driver-1',
        'status': 'accepted',
        'pickup_lat': 42.9849,
        'pickup_lng': 47.5047,
        'dropoff_lat': 42.9764,
        'dropoff_lng': 47.4931,
        'pickup_address': 'Махачкала, точка А',
        'dropoff_address': 'Махачкала, точка Б',
        'tow_truck_type': 'light',
        'price_total': 250000,
        'payment_method': 'cash',
        'created_at': DateTime(2026).toIso8601String(),
      };

  @override
  Future<Map<String, dynamic>?> getCurrentOffer() async => null;

  @override
  Future<void> updateDriverStatus({
    required String driverId,
    required bool isOnline,
    required double? lat,
    required double? lng,
    bool isMock = false,
  }) async {}
}

class _FakeDriverRealTimeNotifier extends DriverRealTimeNotifier {
  _FakeDriverRealTimeNotifier(super.realTimeService);

  @override
  Future<bool> connectAsDriver(String driverId,
      {required String accessToken}) async {
    state = state.copyWith(isConnected: true);
    return true;
  }

  @override
  Future<void> goOnline() async {
    state = state.copyWith(isOnline: true, isConnected: true);
  }

  @override
  void restoreOrder(String orderId, DriverMarkerStatus status) {
    state = state.copyWith(currentOrder: orderId, status: status);
  }
}

class _FakeRealTimeLocationService extends RealTimeLocationService {
  final StreamController<OrderUpdate> _orderUpdates =
      StreamController<OrderUpdate>.broadcast();

  @override
  Stream<OrderUpdate> get orderUpdateStream => _orderUpdates.stream;

  void emitOrderUpdate(OrderUpdate update) {
    _orderUpdates.add(update);
  }

  @override
  void dispose() {
    _orderUpdates.close();
  }
}

class _NoopApiClient implements ApiClient {
  @override
  Future<Map<String, dynamic>> get(String path,
          {Map<String, String>? headers}) async =>
      <String, dynamic>{};

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
  }) async =>
      <String, dynamic>{};

  @override
  Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
  }) async =>
      <String, dynamic>{};

  @override
  Future<Map<String, dynamic>> delete(
    String path, {
    Map<String, String>? headers,
  }) async =>
      <String, dynamic>{};

  @override
  Future<Map<String, dynamic>> patch(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
  }) async =>
      <String, dynamic>{};
}
