import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/features/order/domain/repositories/order_repository.dart';
import 'package:tow_truck_frontend/features/order/presentation/providers/order_provider.dart';
import 'package:tow_truck_frontend/features/driver/data/repository/driver_repository.dart';
import 'package:tow_truck_frontend/features/driver/data/services/driver_location_service.dart';
import 'package:tow_truck_frontend/features/driver/data/services/driver_notification_service.dart';
import 'package:tow_truck_frontend/features/driver/data/services/order_status_service.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver.dart';
import 'driver_provider.dart';

class DriverStatusState {
  const DriverStatusState({
    this.isOnline = false,
    this.isUpdatingOnlineStatus = false,
    this.currentOrder,
    this.availableOrders = const <Order>[],
    this.location,
    this.errorMessage,
    this.hasLocationPermission = true,
    this.isGpsLost = false,
    this.onlineSince,
  });

  final bool isOnline;
  final bool isUpdatingOnlineStatus;
  final Order? currentOrder;
  final List<Order> availableOrders;
  final DriverLocation? location;
  final String? errorMessage;
  final bool hasLocationPermission;
  final bool isGpsLost;
  final DateTime? onlineSince;

  DriverStatusState copyWith({
    bool? isOnline,
    bool? isUpdatingOnlineStatus,
    Order? currentOrder,
    bool clearCurrentOrder = false,
    List<Order>? availableOrders,
    DriverLocation? location,
    String? errorMessage,
    bool clearError = false,
    bool? hasLocationPermission,
    bool? isGpsLost,
    DateTime? onlineSince,
  }) {
    return DriverStatusState(
      isOnline: isOnline ?? this.isOnline,
      isUpdatingOnlineStatus:
          isUpdatingOnlineStatus ?? this.isUpdatingOnlineStatus,
      currentOrder:
          clearCurrentOrder ? null : currentOrder ?? this.currentOrder,
      availableOrders: availableOrders ?? this.availableOrders,
      location: location ?? this.location,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      hasLocationPermission:
          hasLocationPermission ?? this.hasLocationPermission,
      isGpsLost: isGpsLost ?? this.isGpsLost,
      onlineSince: onlineSince ?? this.onlineSince,
    );
  }
}

abstract class DriverStatusController {
  Future<void> toggleOnlineStatus();
  Future<void> updateLocation(double lat, double lng);
  Future<void> acceptOrder(String orderId);
  Future<void> updateOrderStatus(OrderStatus status);
  Future<void> completeOrder(
    String orderId,
    double finalPrice, {
    String? deliveryPhotoPath,
    String? comment,
  });
  Future<void> cancelOrder(String orderId, String reason);
}

class DriverStatusNotifier extends StateNotifier<DriverStatusState>
    implements DriverStatusController {
  DriverStatusNotifier(this.ref)
      : _driverRepository = ref.read(driverRepositoryProvider),
        _orderRepository = ref.read(orderRepositoryProvider),
        super(const DriverStatusState()) {
    _bind();
  }

  final Ref ref;
  final DriverRepository _driverRepository;
  final OrderRepository _orderRepository;
  final DriverLocationService _locationService = DriverLocationService();
  final OrderStatusService _orderStatusService = OrderStatusService();
  final DriverNotificationService _notificationService =
      DriverNotificationService();

  StreamSubscription<Order?>? _currentOrderSubscription;
  StreamSubscription<List<Order>>? _availableOrdersSubscription;

  String? get _driverId => ref.read(authProvider).user?.id;

  void _bind() {
    final driverId = _driverId;
    if (driverId == null) {
      return;
    }

    final driver = ref.read(watchDriverProvider(driverId)).valueOrNull;
    state = state.copyWith(
      isOnline: driver?.isOnline ?? false,
      location: driver?.currentLocation,
      onlineSince: driver?.isOnline == true ? DateTime.now() : null,
    );

    _currentOrderSubscription?.cancel();
    _currentOrderSubscription =
        _orderRepository.watchDriverCurrentOrder(driverId).listen(
      (order) {
        state = state.copyWith(
          currentOrder: order,
          clearCurrentOrder: order == null,
        );
      },
      onError: (Object error) {
        state = state.copyWith(errorMessage: 'Нет соединения с сервером. Проверьте интернет.');
      },
    );

    _subscribeAvailableOrders();
  }

  void _subscribeAvailableOrders() {
    _availableOrdersSubscription?.cancel();
    final location = state.location;
    if (location == null) {
      state = state.copyWith(availableOrders: const <Order>[]);
      return;
    }

    _availableOrdersSubscription = _orderRepository
        .watchAvailableOrders(location.lat, location.lng, 50)
        .listen((orders) async {
      state = state.copyWith(availableOrders: orders);
      if (state.isOnline && state.currentOrder == null && orders.isNotEmpty) {
        await _notificationService.playNewOrderSound();
        await _notificationService.vibrateFeedback(DriverHapticType.warning);
        await _notificationService.showOrderNotification(orders.first);
      }
    }, onError: (Object error) {
      state = state.copyWith(errorMessage: 'Нет соединения с сервером. Проверьте интернет.');
    });
  }

  @override
  Future<void> toggleOnlineStatus() async {
    final driverId = _driverId;
    if (driverId == null) {
      return;
    }

    state = state.copyWith(
      isUpdatingOnlineStatus: true,
      clearError: true,
    );

    try {
      if (!state.isOnline) {
        await _locationService.checkPermissions();
        final position = await _locationService.getCurrentPosition();
        final location = DriverLocation(
          lat: position.latitude,
          lng: position.longitude,
        );

        await _driverRepository.setDriverOnlineStatus(driverId, true);
        await _driverRepository.updateDriverLocation(driverId, location);
        await _locationService.startLocationTracking(
          driverId: driverId,
          onPosition: (position) {
            updateLocation(position.latitude, position.longitude);
          },
        );

        state = state.copyWith(
          isOnline: true,
          isUpdatingOnlineStatus: false,
          location: location,
          hasLocationPermission: true,
          isGpsLost: false,
          onlineSince: DateTime.now(),
        );
        _subscribeAvailableOrders();
        return;
      }

      await _locationService.stopLocationTracking();
      await _driverRepository.setDriverOnlineStatus(driverId, false);
      state = state.copyWith(
        isOnline: false,
        isUpdatingOnlineStatus: false,
        availableOrders: const <Order>[],
        onlineSince: null,
      );
    } catch (error) {
      state = state.copyWith(
        isUpdatingOnlineStatus: false,
        hasLocationPermission: false,
        errorMessage: 'Нет соединения с сервером. Проверьте интернет.',
      );
    }
  }

  @override
  Future<void> updateLocation(double lat, double lng) async {
    final driverId = _driverId;
    if (driverId == null || !state.isOnline) {
      return;
    }

    try {
      final location = DriverLocation(lat: lat, lng: lng);
      state = state.copyWith(location: location, isGpsLost: false);
      await _driverRepository.updateDriverLocation(driverId, location);
      _subscribeAvailableOrders();
    } catch (error) {
      state = state.copyWith(
        isGpsLost: true,
        errorMessage:
            'Проблемы с GPS. Проверьте настройки.',
      );
    }
  }

  @override
  Future<void> acceptOrder(String orderId) async {
    final driverId = _driverId;
    if (driverId == null) {
      return;
    }

    try {
      final order =
          state.availableOrders.firstWhere((item) => item.id == orderId);
      await _orderRepository.acceptOrder(orderId, driverId);
      state = state.copyWith(
          currentOrder: order.copyWith(
        driverId: driverId,
        status: OrderStatus.assigned,
        assignedAt: DateTime.now(),
      ));
      await _notificationService.vibrateFeedback(DriverHapticType.success);
    } catch (_) {
      state = state.copyWith(
        errorMessage: 'Ошибка при принятии заказа. Попробуйте снова.',
      );
    }
  }

  @override
  Future<void> updateOrderStatus(OrderStatus status) async {
    final order = state.currentOrder;
    if (order == null) {
      return;
    }

    await _orderRepository.updateOrderStatus(order.id, status);
    state = state.copyWith(currentOrder: order.copyWith(status: status));
  }

  @override
  Future<void> completeOrder(
    String orderId,
    double finalPrice, {
    String? deliveryPhotoPath,
    String? comment,
  }) async {
    if (deliveryPhotoPath != null && deliveryPhotoPath.isNotEmpty) {
      await _orderStatusService.uploadDeliveryPhoto(orderId, deliveryPhotoPath);
    }

    await _orderRepository.completeOrder(orderId, finalPrice);
    state = state.copyWith(clearCurrentOrder: true);
  }

  @override
  Future<void> cancelOrder(String orderId, String reason) async {
    await _orderRepository.cancelOrder(orderId, reason: reason);
    state = state.copyWith(clearCurrentOrder: true);
  }

  @override
  void dispose() {
    _currentOrderSubscription?.cancel();
    _availableOrdersSubscription?.cancel();
    _locationService.dispose();
    _notificationService.dispose();
    super.dispose();
  }
}

final driverStatusProvider =
    StateNotifierProvider<DriverStatusNotifier, DriverStatusState>((ref) {
  return DriverStatusNotifier(ref);
});

final driverStatusControllerProvider = Provider<DriverStatusController>((ref) {
  return ref.read(driverStatusProvider.notifier);
});

final driverHomeStatusProvider = Provider<DriverStatusState>((ref) {
  return ref.watch(driverStatusProvider);
});
