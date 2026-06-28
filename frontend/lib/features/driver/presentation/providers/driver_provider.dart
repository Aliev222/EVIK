import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/network/api_client_stub.dart'
    if (dart.library.io) '../../../../core/network/api_client_io.dart'
    as platform_api;
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'package:tow_truck_frontend/features/driver/data/repository/driver_repository.dart';
import 'package:tow_truck_frontend/features/driver/data/repository_impl/http_driver_repository.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';

// Driver Repository Provider
final driverRepositoryProvider = Provider<DriverRepository>((ref) {
  final accessToken =
      ref.watch(authProvider.select((state) => state.accessToken));
  return HttpDriverRepository(
    apiClient: platform_api.createPlatformApiClient(),
    accessToken: accessToken,
  );
});

// Driver State для UI
class DriverState {
  const DriverState({
    this.driver,
    this.isLoading = false,
    this.errorMessage,
  });

  final Driver? driver;
  final bool isLoading;
  final String? errorMessage;

  DriverState copyWith({
    Driver? driver,
    bool? isLoading,
    String? errorMessage,
  }) {
    return DriverState(
      driver: driver ?? this.driver,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  bool get isOnline => driver?.isOnline ?? false;
  bool get isVerified => driver?.isVerified ?? false;
}

// Driver State Notifier
class DriverNotifier extends StateNotifier<DriverState> {
  DriverNotifier(this._repository) : super(const DriverState());

  final DriverRepository _repository;

  /// Создать профиль водителя
  Future<void> createDriverProfile({
    required String userId,
    required String vehicleModel,
    required String vehicleNumber,
    required VehicleType vehicleType,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final driver = Driver(
        userId: userId,
        vehicleModel: vehicleModel,
        vehicleNumber: vehicleNumber,
        vehicleType: vehicleType,
        rating: 0.0, // рейтинг обновится после первых отзывов
        totalOrders: 0,
        isOnline: false,
        currentLocation: null,
        isVerified: false, // админ должен верифицировать
        earnings: const DriverEarnings(today: 0, week: 0, month: 0),
      );

      await _repository.createDriver(driver);
      state = state.copyWith(driver: driver, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Произошла ошибка. Попробуйте позже.',
      );
    }
  }

  /// Переключить онлайн статус
  Future<void> toggleOnlineStatus() async {
    final driver = state.driver;
    if (driver == null) return;

    try {
      final newStatus = !driver.isOnline;
      await _repository.setDriverOnlineStatus(driver.userId, newStatus);
      // Статус обновится автоматически через watchDriver
    } catch (e) {
      state = state.copyWith(errorMessage: 'Ошибка переключения статуса. Попробуйте позже.');
    }
  }

  /// Обновить местоположение водителя
  Future<void> updateLocation(double lat, double lng) async {
    final driver = state.driver;
    if (driver == null) return;

    try {
      final location = DriverLocation(lat: lat, lng: lng);
      await _repository.updateDriverLocation(driver.userId, location);
    } catch (e) {
      state = state.copyWith(errorMessage: 'Не удалось обновить местоположение.');
    }
  }

  void clearError() {
    state = state.copyWith(errorMessage: null);
  }
}

// Driver State Provider
final driverProvider =
    StateNotifierProvider<DriverNotifier, DriverState>((ref) {
  final repository = ref.watch(driverRepositoryProvider);
  return DriverNotifier(repository);
});

// Watch specific driver
final watchDriverProvider =
    StreamProvider.family<Driver?, String>((ref, userId) {
  final repository = ref.watch(driverRepositoryProvider);
  return repository.watchDriver(userId);
});

// Watch online drivers
final watchOnlineDriversProvider = StreamProvider<List<Driver>>((ref) {
  final repository = ref.watch(driverRepositoryProvider);
  return repository.watchOnlineDrivers();
});
