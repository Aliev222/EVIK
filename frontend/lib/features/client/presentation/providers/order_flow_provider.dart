import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tow_truck_frontend/core/constants/app_constants.dart';
import 'package:tow_truck_frontend/core/services/location_service.dart';
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/new_driver_provider.dart';
import 'package:tow_truck_frontend/features/map/domain/entities/map_location.dart';
import 'package:tow_truck_frontend/features/order/data/repository_impl/http_order_repository.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order_flow_state.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/tariff.dart';
import 'package:tow_truck_frontend/features/order/domain/repositories/order_repository.dart';
import 'package:tow_truck_frontend/features/order/presentation/providers/order_provider.dart';
import 'payment_wallet_provider.dart';

final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

final selectedOrderPaymentMethodProvider = StateProvider<PaymentMethod>((ref) {
  return PaymentMethod.cash;
});

class OrderFlowNotifier extends StateNotifier<OrderFlowState> {
  OrderFlowNotifier(this._ref) : super(const OrderFlowState()) {
    unawaited(restoreActiveFlow());
  }

  final Ref _ref;
  Timer? _searchTimer;
  Timer? _driverFoundTimer;
  Timer? _orderPollTimer;
  Timer? _paymentPollTimer;
  int _priceRequestSeq = 0;

  static const _activeOrderIdKey = 'client_active_order_id';

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
    unawaited(_loadTariffs());
  }

  Future<void> _loadTariffs() async {
    if (state.tariffs.isNotEmpty) return;
    try {
      final repo = _ref.read(orderRepositoryProvider);
      final list = await repo.getTariffs();
      if (list.isEmpty) return;
      final map = <TowTruckType, Tariff>{
        for (final t in list) t.towTruckType: t,
      };
      state = state.copyWith(tariffs: map);
    } catch (_) {
      // best-effort: ошибка загрузки тарифов не блокирует выбор
    }
  }

  /// Локальная оценка цены по уже загруженным тарифам (формула как на бэке:
  /// base + distance*pricePerKm, минимум minimumPrice, результат в рублях).
  /// Позволяет показать цену для каждого типа эвакуатора без ожидания сервера.
  double? localPriceFor(TowTruckType type) {
    final t = state.tariffs[type];
    if (t == null || state.distance <= 0) return null;
    final distanceKopecks = (state.distance * t.pricePerKm);
    var total = t.basePrice + distanceKopecks;
    if (total < t.minimumPrice) total = t.minimumPrice.toDouble();
    return total / 100;
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

  Future<bool> goToDriverSearch() async {
    if (state.selectedTowTruckType == null) {
      state = state.copyWith(errorMessage: 'Выберите тип эвакуатора');
      return false;
    }
    return _createOrderWithPaymentFlow();
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
    state = state.copyWith(currentStep: OrderFlowStep.completion);
  }

  void goToRating() {
    state = state.copyWith(currentStep: OrderFlowStep.rating);
  }

  void resetFlow() {
    _searchTimer?.cancel();
    _driverFoundTimer?.cancel();
    _orderPollTimer?.cancel();
    _paymentPollTimer?.cancel();
    unawaited(_clearPersistedActiveOrder());
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
    unawaited(_updatePrice());
  }

  void selectTowTruckType(TowTruckType towTruckType) {
    state = state.copyWith(
      selectedTowTruckType: towTruckType,
      errorMessage: null,
    );
    unawaited(_updatePrice());
  }

  void selectPaymentMethod(PaymentMethod paymentMethod) {
    _ref.read(selectedOrderPaymentMethodProvider.notifier).state =
        paymentMethod;
    state = state.copyWith(
      selectedPaymentMethod: paymentMethod,
      errorMessage: null,
    );
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

  Future<bool> _createOrderWithPaymentFlow() async {
    if (state.pickupLocation == null ||
        state.destinationLocation == null ||
        state.selectedVehicleType == null) {
      _handleSearchError('Не заполнены обязательные параметры заказа');
      return false;
    }

    final auth = _ref.read(authProvider);
    final clientId = auth.user?.id;
    if (clientId == null || clientId.isEmpty) {
      _handleSearchError('Нужно войти в аккаунт, чтобы создать заказ.');
      return false;
    }

    final command = CreateOrderCommand(
      clientId: clientId,
      pickupLocation: state.pickupLocation!.toLocationModel(),
      dropoffLocation: state.destinationLocation!.toLocationModel(),
      vehicleType: state.selectedVehicleType!,
      distance: state.distance,
      estimatedPrice: state.estimatedPrice,
      paymentMethod: _ref.read(selectedOrderPaymentMethodProvider),
      towTruckType: state.selectedTowTruckType,
      notes: _buildOrderNotes(),
    );

    try {
      state = state.copyWith(
        isLoading: true,
        errorMessage: null,
      );
      await _ref.read(orderProvider.notifier).createOrder(command);
      final created = _ref.read(orderProvider).currentOrder;
      if (created == null) {
        _handleSearchError(
          _ref.read(orderProvider).errorMessage ??
              'Не удалось создать заказ на сервере.',
        );
        return false;
      }

      await _persistActiveOrder(created.id);
      _beginDriverSearchTimers(created.id);
      return true;
    } catch (error) {
      _handleSearchError('Ошибка при поиске водителя. Попробуйте снова.');
      return false;
    }
  }

  void _beginDriverSearchTimers(String orderId) {
    _searchTimer?.cancel();
    state = state.copyWith(
      currentStep: OrderFlowStep.driverSearch,
      isLoading: true,
      isPaymentProcessing: false,
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
    _startOrderPolling(orderId);
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
      // If we don't have driver data yet, fetch it from the backend
      if (assignedDriver == null || assignedDriver.userId != order.driverId) {
        _fetchDriverProfile(order.driverId!);
      }
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

    if (order.status == OrderStatus.awaitingPayment) {
      _searchTimer?.cancel();
      _orderPollTimer?.cancel();
      nextStep = OrderFlowStep.paymentConfirmation;
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

  /// Fetches real driver profile data from the backend API
  Future<void> _fetchDriverProfile(String driverId) async {
    try {
      final driverRepository = _ref.read(httpDriverRepositoryProvider);
      final driver = await driverRepository.getDriver(driverId);

      if (mounted && driver != null) {
        state = state.copyWith(assignedDriver: driver);
      }
    } catch (error) {
      // If we can't fetch driver data, we'll continue without it
      // Rather than showing synthetic data, we'll handle this gracefully in the UI
      // Error is logged internally by the API client
    }
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
    _paymentPollTimer?.cancel();
    state = state.copyWith(
      isLoading: false,
      isPaymentProcessing: false,
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
    unawaited(_updatePrice());
  }

  Future<void> _updatePrice() async {
    final pickup = state.pickupLocation;
    final dropoff = state.destinationLocation;
    final towTruckType = state.selectedTowTruckType;
    if (pickup == null || dropoff == null || towTruckType == null) return;

    final repo = _ref.read(orderRepositoryProvider);
    if (repo is! HttpOrderRepository) return;

    final seq = ++_priceRequestSeq;
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final quote = await repo.calculatePrice(
        pickup: pickup.toLocationModel(),
        dropoff: dropoff.toLocationModel(),
        towTruckType: towTruckType,
      );
      // Игнорируем устаревший ответ, если пользователь успел переключить тип.
      if (!mounted || seq != _priceRequestSeq) return;
      state = state.copyWith(
        distance: quote.distanceKm,
        estimatedPrice: quote.totalPrice / 100,
        isLoading: false,
        errorMessage: null,
      );
    } catch (error) {
      if (!mounted || seq != _priceRequestSeq) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Не удалось рассчитать цену. Попробуйте позже.',
      );
    }
  }

  Future<void> restoreActiveFlow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final orderId = prefs.getString(_activeOrderIdKey);
      if (orderId == null || orderId.isEmpty) return;

      final repo = _ref.read(orderRepositoryProvider);
      final order = await repo.getOrder(orderId);
      if (!mounted || order == null) return;

      state = state.copyWith(
        activeOrder: order,
        currentStep: order.status == OrderStatus.completed
            ? OrderFlowStep.completion
            : _stepForRestoredOrder(order),
        estimatedPrice: order.finalPrice ?? order.estimatedPrice,
        isLoading: false,
      );

      if (repo is HttpOrderRepository) {
        try {
          final payment = await repo.getOrderPaymentStatus(orderId);
          final priceRub = payment.amount / 100;
          state = state.copyWith(
            activeOrder: order.copyWith(
              estimatedPrice: priceRub,
              finalPrice: priceRub,
              paymentMethod: payment.paymentMethod,
              paymentId: payment.id,
              paymentStatus: payment.status,
              paymentConfirmationUrl: payment.confirmationUrl,
            ),
            selectedPaymentMethod: payment.paymentMethod,
            estimatedPrice: priceRub,
          );
          _ref.read(selectedOrderPaymentMethodProvider.notifier).state =
              payment.paymentMethod;
        } catch (_) {
          // Order restore is still useful if the payment endpoint is transiently unavailable.
        }
      }

      if (order.status == OrderStatus.completed) {
        await loadReceipt(orderId);
      } else {
        _beginDriverSearchTimers(orderId);
      }
    } catch (_) {
      // Restore is best-effort; a failed restore must not block a new order.
    }
  }

  Future<void> loadReceipt([String? orderId]) async {
    final id = orderId ?? state.activeOrder?.id;
    if (id == null || id.isEmpty) return;
    state = state.copyWith(isReceiptLoading: true, receiptError: null);
    try {
      final receipt =
          await _ref.read(paymentRepositoryProvider).getOrderReceipt(id);
      if (!mounted) return;
      state = state.copyWith(
        receipt: receipt,
        isReceiptLoading: false,
        receiptError: null,
      );
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        isReceiptLoading: false,
        receiptError: 'Не удалось загрузить чек. Попробуйте позже.',
      );
    }
  }

  OrderFlowStep _stepForRestoredOrder(Order order) {
    return switch (order.status) {
      OrderStatus.searching => OrderFlowStep.driverSearch,
      OrderStatus.assigned => OrderFlowStep.driverFound,
      OrderStatus.onWay ||
      OrderStatus.arrived ||
      OrderStatus.evacuating =>
        OrderFlowStep.tracking,
      OrderStatus.awaitingPayment => OrderFlowStep.paymentConfirmation,
      OrderStatus.completed => OrderFlowStep.completion,
      OrderStatus.cancelled => OrderFlowStep.idle,
    };
  }

  Future<void> _persistActiveOrder(String orderId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeOrderIdKey, orderId);
  }

  Future<void> _clearPersistedActiveOrder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeOrderIdKey);
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
