import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/services/price_calculator.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../driver/domain/entities/driver.dart';
import '../../../map/domain/entities/map_location.dart';
import '../../../order/domain/entities/order.dart';
import '../../../order/domain/entities/order_flow_state.dart';
import '../../../order/domain/repositories/order_repository.dart';
import '../../../order/presentation/providers/order_provider.dart';

final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

final priceCalculatorProvider = Provider<PriceCalculator>((ref) {
  return PriceCalculator(locationService: ref.read(locationServiceProvider));
});

class OrderFlowNotifier extends StateNotifier<OrderFlowState> {
  OrderFlowNotifier(this._ref) : super(const OrderFlowState());

  final Ref _ref;
  Timer? _searchTimer;
  Timer? _driverFoundTimer;
  Timer? _orderPollTimer;

  void startOrderFlow() {
    state = state.copyWith(
      currentStep: OrderFlowStep.pickupSelection,
      errorMessage: null,
    );
  }

  void goToDestinationSelection() {
    if (state.pickupLocation == null) {
      state = state.copyWith(errorMessage: 'Сначала выберите точку подачи');
      return;
    }
    state = state.copyWith(
      currentStep: OrderFlowStep.destinationSelection,
      errorMessage: null,
    );
  }

  void goToVehicleSelection() {
    if (state.destinationLocation == null) {
      state = state.copyWith(errorMessage: 'Сначала выберите адрес доставки');
      return;
    }
    _calculateDistanceAndPrice();
    state = state.copyWith(
      currentStep: OrderFlowStep.vehicleSelection,
      errorMessage: null,
    );
  }

  void goToTowTruckSelection() {
    if (state.selectedVehicleType == null) {
      state = state.copyWith(errorMessage: 'Выберите тип автомобиля');
      return;
    }
    state = state.copyWith(
      currentStep: OrderFlowStep.towTruckSelection,
      errorMessage: null,
    );
  }

  void goToDriverSearch() {
    if (state.selectedTowTruckType == null) {
      state = state.copyWith(errorMessage: 'Выберите тип эвакуатора');
      return;
    }
    _startDriverSearch();
  }

  void goToDriverFound() {
    state = state.copyWith(
      currentStep: OrderFlowStep.driverFound,
      isLoading: false,
      errorMessage: null,
    );
  }

  void goToTracking() {
    final order = state.activeOrder;
    state = state.copyWith(
      currentStep: OrderFlowStep.tracking,
      activeOrder: order?.copyWith(status: OrderStatus.onWay),
    );
  }

  void goToCompletion() {
    final order = state.activeOrder;
    state = state.copyWith(
      currentStep: OrderFlowStep.completion,
      activeOrder: order?.copyWith(
        status: OrderStatus.completed,
        finalPrice: state.estimatedPrice,
        completedAt: DateTime.now(),
      ),
    );
  }

  void goToRating() {
    state = state.copyWith(currentStep: OrderFlowStep.rating);
  }

  void resetFlow() {
    _searchTimer?.cancel();
    _driverFoundTimer?.cancel();
    _orderPollTimer?.cancel();
    state = const OrderFlowState();
  }

  void setPickupLocation(MapLocation location) {
    state = state.copyWith(pickupLocation: location, errorMessage: null);
  }

  void setDestinationLocation(MapLocation location) {
    state = state.copyWith(destinationLocation: location, errorMessage: null);
    _calculateDistanceAndPrice();
  }

  void selectVehicleType(VehicleType vehicleType) {
    state = state.copyWith(
      selectedVehicleType: vehicleType,
      errorMessage: null,
    );
    _updatePrice();
  }

  void selectTowTruckType(TowTruckType towTruckType) {
    state = state.copyWith(
      selectedTowTruckType: towTruckType,
      errorMessage: null,
    );
    _updatePrice();
  }

  void setBlockedWheelsCount(int count) {
    state = state.copyWith(blockedWheelsCount: count.clamp(0, 4));
  }

  void setClientComment(String comment) {
    state = state.copyWith(clientComment: comment.trim());
  }

  Future<void> detectCurrentLocation() async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final locationService = _ref.read(locationServiceProvider);
      final locationModel = await locationService.getCurrentLocation();

      final location = locationModel == null
          ? const MapLocation(
              latitude: AppConstants.moscowLat,
              longitude: AppConstants.moscowLng,
              address: 'Москва, центр',
              description: 'Адрес определен приблизительно',
            )
          : MapLocation(
              latitude: locationModel.lat,
              longitude: locationModel.lng,
              address: locationModel.address,
              description: 'Определено автоматически',
            );

      state = state.copyWith(
        pickupLocation: location,
        isLoading: false,
        errorMessage: null,
      );
    } catch (_) {
      state = state.copyWith(
        pickupLocation: const MapLocation(
          latitude: AppConstants.moscowLat,
          longitude: AppConstants.moscowLng,
          address: 'Москва, центр',
          description: 'Fallback location',
        ),
        isLoading: false,
        errorMessage:
            'Не удалось получить точную геолокацию. Используем центр Москвы.',
      );
    }
  }

  void cancelSearch() {
    _searchTimer?.cancel();
    _driverFoundTimer?.cancel();
    _orderPollTimer?.cancel();
    final orderNotifier = _ref.read(orderProvider.notifier);
    unawaited(orderNotifier.cancelCurrentOrder(reason: 'Отменено клиентом'));
    resetFlow();
  }

  void clearError() {
    state = state.copyWith(errorMessage: null);
  }

  void _startDriverSearch() {
    _searchTimer?.cancel();
    _driverFoundTimer?.cancel();

    state = state.copyWith(
      currentStep: OrderFlowStep.driverSearch,
      isLoading: true,
      searchDurationSeconds: 0,
      errorMessage: null,
    );

    _searchTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final seconds = state.searchDurationSeconds + 1;
      state = state.copyWith(searchDurationSeconds: seconds);
      if (seconds >= 120) {
        _handleSearchTimeout();
      }
    });

    unawaited(_createOrderWithFallback());
    if (AppConstants.useMockData) {
      _driverFoundTimer = Timer(const Duration(seconds: 4), _assignMockDriver);
    }
  }

  Future<void> _createOrderWithFallback() async {
    if (state.pickupLocation == null ||
        state.destinationLocation == null ||
        state.selectedVehicleType == null) {
      _handleSearchError('Не заполнены обязательные параметры заказа');
      return;
    }

    final auth = _ref.read(authProvider);
    final clientId = auth.user?.id;
    if (clientId == null || clientId.isEmpty) {
      _handleSearchError('Нужно войти в аккаунт, чтобы создать заказ.');
      return;
    }

    final command = CreateOrderCommand(
      clientId: clientId,
      pickupLocation: state.pickupLocation!.toLocationModel(),
      dropoffLocation: state.destinationLocation!.toLocationModel(),
      vehicleType: state.selectedVehicleType!,
      distance: state.distance,
      estimatedPrice: state.estimatedPrice,
      paymentMethod: PaymentMethod.cash,
      towTruckType: state.selectedTowTruckType,
      notes: _buildOrderNotes(),
    );

    try {
      await _ref.read(orderProvider.notifier).createOrder(command);
      final created = _ref.read(orderProvider).currentOrder;
      if (created == null) {
        if (AppConstants.useMockData) {
          state = state.copyWith(activeOrder: _mockOrder(command));
          return;
        }
        _handleSearchError(
          _ref.read(orderProvider).errorMessage ??
              'РќРµ СѓРґР°Р»РѕСЃСЊ СЃРѕР·РґР°С‚СЊ Р·Р°РєР°Р· РЅР° СЃРµСЂРІРµСЂРµ.',
        );
        return;
      }

      state = state.copyWith(activeOrder: created);
      if (!AppConstants.useMockData) {
        _startOrderPolling(created.id);
      }
    } catch (error) {
      if (AppConstants.useMockData) {
        state = state.copyWith(activeOrder: _mockOrder(command));
        return;
      }
      _handleSearchError(
          'РќРµ СѓРґР°Р»РѕСЃСЊ СЃРѕР·РґР°С‚СЊ Р·Р°РєР°Р·: $error');
    }
  }

  void _startOrderPolling(String orderId) {
    _orderPollTimer?.cancel();
    _orderPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      unawaited(_refreshActiveOrder(orderId));
    });
    unawaited(_refreshActiveOrder(orderId));
  }

  Future<void> _refreshActiveOrder(String orderId) async {
    try {
      final order = await _ref.read(orderRepositoryProvider).getOrder(orderId);
      if (!mounted || order == null) return;
      _applyBackendOrderUpdate(order);
    } catch (_) {
      // Keep the visible flow stable during transient local-server failures.
    }
  }

  void _applyBackendOrderUpdate(Order order) {
    var nextStep = state.currentStep;
    var assignedDriver = state.assignedDriver;

    if (order.driverId != null && order.driverId!.isNotEmpty) {
      assignedDriver ??= _driverFromAcceptedOrder(order);
      if (nextStep == OrderFlowStep.driverSearch) {
        _searchTimer?.cancel();
        nextStep = OrderFlowStep.driverFound;
      }
    }

    if (order.status == OrderStatus.arrived ||
        order.status == OrderStatus.evacuating) {
      if (nextStep == OrderFlowStep.driverFound) {
        nextStep = OrderFlowStep.tracking;
      }
    }

    if (order.status == OrderStatus.completed) {
      _searchTimer?.cancel();
      _orderPollTimer?.cancel();
      nextStep = OrderFlowStep.completion;
    }

    if (order.status == OrderStatus.cancelled) {
      _searchTimer?.cancel();
      _orderPollTimer?.cancel();
      state = state.copyWith(
        activeOrder: order,
        currentStep: OrderFlowStep.idle,
        isLoading: false,
        errorMessage: 'Order was cancelled.',
      );
      return;
    }

    state = state.copyWith(
      activeOrder: order,
      assignedDriver: assignedDriver,
      currentStep: nextStep,
      isLoading: false,
      errorMessage: null,
    );
  }

  Driver _driverFromAcceptedOrder(Order order) {
    final driverId = order.driverId ?? 'driver';
    return Driver(
      userId: driverId,
      vehicleModel: state.selectedTowTruckType?.displayName ?? 'EVIK tow truck',
      vehicleNumber: 'EVIK',
      vehicleType: VehicleType.light,
      rating: 5,
      totalOrders: 0,
      isOnline: true,
      currentLocation: DriverLocation(
        lat: order.pickupLocation.lat + 0.012,
        lng: order.pickupLocation.lng + 0.010,
      ),
      isVerified: true,
      earnings: const DriverEarnings(today: 0, week: 0, month: 0),
    );
  }

  String? _buildOrderNotes() {
    final parts = <String>[];
    if (state.blockedWheelsCount > 0) {
      parts.add('Заблокировано колес: ${state.blockedWheelsCount}');
    }
    if (state.clientComment.trim().isNotEmpty) {
      parts.add('Комментарий клиента: ${state.clientComment.trim()}');
    }
    return parts.isEmpty ? null : parts.join('\n');
  }

  Order _mockOrder(CreateOrderCommand command) {
    return Order(
      id: 'mock_${DateTime.now().millisecondsSinceEpoch}',
      clientId: command.clientId,
      status: OrderStatus.searching,
      pickupLocation: command.pickupLocation,
      dropoffLocation: command.dropoffLocation,
      vehicleType: command.vehicleType,
      distance: command.distance,
      estimatedPrice: command.estimatedPrice,
      paymentMethod: command.paymentMethod,
      createdAt: DateTime.now(),
    );
  }

  void _assignMockDriver() {
    if (!mounted || state.currentStep != OrderFlowStep.driverSearch) return;

    final random = Random();
    final driverId = 'driver_${1000 + random.nextInt(9000)}';
    final activeOrder = state.activeOrder?.copyWith(
      driverId: driverId,
      status: OrderStatus.assigned,
      assignedAt: DateTime.now(),
    );

    state = state.copyWith(
      activeOrder: activeOrder,
      assignedDriver: Driver(
        userId: driverId,
        vehicleModel:
            state.selectedTowTruckType?.displayName ?? 'Эвакуатор EVIK',
        vehicleNumber: 'А${100 + random.nextInt(900)}АА 777',
        vehicleType: VehicleType.light,
        rating: 4.7 + random.nextDouble() * 0.3,
        totalOrders: 80 + random.nextInt(220),
        isOnline: true,
        currentLocation: const DriverLocation(
          lat: AppConstants.moscowLat,
          lng: AppConstants.moscowLng,
        ),
        isVerified: true,
        earnings: const DriverEarnings(today: 0, week: 0, month: 0),
      ),
    );
    _searchTimer?.cancel();
    goToDriverFound();
  }

  void _handleSearchTimeout() {
    _searchTimer?.cancel();
    _driverFoundTimer?.cancel();
    _orderPollTimer?.cancel();
    state = state.copyWith(
      isLoading: false,
      errorMessage:
          'Не удалось найти свободного водителя. Попробуйте повторить поиск.',
    );
  }

  void _handleSearchError(String error) {
    _searchTimer?.cancel();
    _driverFoundTimer?.cancel();
    _orderPollTimer?.cancel();
    state = state.copyWith(
      isLoading: false,
      errorMessage: error,
    );
  }

  void _calculateDistanceAndPrice() {
    if (state.pickupLocation == null || state.destinationLocation == null) {
      return;
    }

    final distance = Geolocator.distanceBetween(
          state.pickupLocation!.latitude,
          state.pickupLocation!.longitude,
          state.destinationLocation!.latitude,
          state.destinationLocation!.longitude,
        ) /
        1000;

    state = state.copyWith(distance: distance);
    _updatePrice();
  }

  void _updatePrice() {
    final vehicleType = state.selectedVehicleType;
    if (vehicleType == null) return;

    final basePrice = switch (vehicleType) {
      VehicleType.light => 1500.0,
      VehicleType.suv => 1800.0,
      VehicleType.minibus => 2200.0,
      VehicleType.truck => 2800.0,
    };

    final towTruckMultiplier = switch (state.selectedTowTruckType) {
      TowTruckType.winch => 1.0,
      TowTruckType.platform => 1.2,
      TowTruckType.manipulator => 1.5,
      null => 1.0,
    };

    final distancePrice = max(state.distance, 1) * 50.0;
    state = state.copyWith(
      estimatedPrice: (basePrice + distancePrice) * towTruckMultiplier,
    );
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _driverFoundTimer?.cancel();
    _orderPollTimer?.cancel();
    super.dispose();
  }
}

final orderFlowProvider =
    StateNotifierProvider<OrderFlowNotifier, OrderFlowState>((ref) {
  return OrderFlowNotifier(ref);
});

final canProceedToDestinationProvider = Provider<bool>((ref) {
  return ref.watch(orderFlowProvider).pickupLocation != null;
});

final canProceedToVehicleSelectionProvider = Provider<bool>((ref) {
  final state = ref.watch(orderFlowProvider);
  return state.pickupLocation != null && state.destinationLocation != null;
});

final canProceedToTowTruckSelectionProvider = Provider<bool>((ref) {
  final state = ref.watch(orderFlowProvider);
  return state.pickupLocation != null &&
      state.destinationLocation != null &&
      state.selectedVehicleType != null;
});

final canStartSearchProvider = Provider<bool>((ref) {
  final state = ref.watch(orderFlowProvider);
  return state.pickupLocation != null &&
      state.destinationLocation != null &&
      state.selectedVehicleType != null &&
      state.selectedTowTruckType != null;
});

final formattedEstimatedPriceProvider = Provider<String>((ref) {
  final price = ref.watch(orderFlowProvider).estimatedPrice;
  if (price <= 0) return 'Расчет...';
  return '${price.round()} ₽';
});

final formattedDistanceProvider = Provider<String>((ref) {
  final distance = ref.watch(orderFlowProvider).distance;
  if (distance <= 0) return '';
  return '${distance.toStringAsFixed(1)} км';
});

final searchTimerDisplayProvider = Provider<String>((ref) {
  final secondsTotal = ref.watch(orderFlowProvider).searchDurationSeconds;
  final minutes = secondsTotal ~/ 60;
  final seconds = secondsTotal % 60;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
});
