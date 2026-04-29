import 'package:tow_truck_frontend/features/auth/domain/entities/user.dart';
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'package:tow_truck_frontend/features/client/presentation/screens/client_home_screen.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver_earnings.dart';
import 'package:tow_truck_frontend/features/driver/data/repository/driver_verification_repository.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/available_orders_provider.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/driver_earnings_provider.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/driver_moderation_provider.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/driver_status_provider.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/driver_provider.dart';
import 'package:tow_truck_frontend/features/driver/presentation/screens/driver_main_screen.dart';
import 'package:tow_truck_frontend/features/map/domain/entities/map_location.dart';
import 'package:tow_truck_frontend/features/map/presentation/providers/map_provider.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ClientHomeScreen renders on phone size', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(
            User(
              id: 'client',
              phone: '+79990000000',
              fullName: 'Client',
              role: UserRole.client,
              isActive: true,
              createdAt: DateTime(2026, 4, 24),
              lastSeen: DateTime(2026, 4, 24),
            ),
          ),
          mapProvider.overrideWith((ref) => _TestMapNotifier()),
        ],
        child: const MaterialApp(home: ClientHomeScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Клиент'), findsOneWidget);
    expect(find.text('Вызвать эвакуатор'), findsOneWidget);
  });

  testWidgets('DriverHomeScreen renders on landscape tablet size',
      (tester) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(
            User(
              id: 'driver',
              phone: '+79990000000',
              fullName: 'Driver',
              role: UserRole.driver,
              isActive: true,
              createdAt: DateTime(2026, 4, 24),
              lastSeen: DateTime(2026, 4, 24),
            ),
          ),
          watchDriverModerationProvider.overrideWith(
            (ref, userId) => Stream<DriverVerificationDocument?>.value(null),
          ),
          watchDriverProvider.overrideWith(
            (ref, userId) => Stream<Driver?>.value(
              const Driver(
                userId: 'driver',
                vehicleModel: 'Ford Transit',
                vehicleNumber: 'А111АА77',
                vehicleType: VehicleType.light,
                rating: 4.9,
                totalOrders: 50,
                isOnline: false,
                currentLocation: DriverLocation(lat: 55.75, lng: 37.61),
                isVerified: true,
                earnings: DriverEarnings(today: 0, week: 0, month: 0),
              ),
            ),
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
          driverHomeEarningsProvider.overrideWith(
            (ref) => const DriverEarningsState(
              stats: EarningsStats.zero,
              isLoading: false,
            ),
          ),
        ],
        child: const MaterialApp(home: DriverMainScreen()),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Водитель'), findsOneWidget);
    expect(find.text('Начать работу'), findsOneWidget);
  });
}

class _TestMapNotifier extends MapNotifier {
  @override
  Future<void> getCurrentLocation() async {
    state = state.copyWith(
      currentPosition: const MapLocation(
        latitude: 55.7539,
        longitude: 37.6208,
        address: 'Красная площадь, Москва',
      ),
      cameraPosition: const MapLocation(
        latitude: 55.7539,
        longitude: 37.6208,
        address: 'Красная площадь, Москва',
      ),
      permissionGranted: true,
      isLoading: false,
      error: null,
    );
  }
}

class _NoopDriverStatusController implements DriverStatusController {
  const _NoopDriverStatusController();

  @override
  Future<void> acceptOrder(String orderId) async {}

  @override
  Future<void> cancelOrder(String orderId, String reason) async {}

  @override
  Future<void> completeOrder(
    String orderId,
    double finalPrice, {
    String? deliveryPhotoPath,
    String? comment,
  }) async {}

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
