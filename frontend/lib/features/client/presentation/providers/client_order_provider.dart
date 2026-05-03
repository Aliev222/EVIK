import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../map/domain/entities/map_location.dart';
import '../../../order/domain/entities/order.dart';
import '../../../order/domain/repositories/order_repository.dart';
import '../../../order/presentation/providers/order_provider.dart';
import '../../data/services/pricing_service.dart';

enum ClientHomeUIState {
  idle,
  selectingPickup,
  selectingDropoff,
  fillingOrder,
  searching,
  driverAssigned,
  driverArriving,
  evacuating,
  completed,
}

class OrderFormData {
  const OrderFormData({
    this.vehicleType = VehicleType.light,
    this.description = '',
    this.phoneNumber = '',
    this.paymentMethod = PaymentMethod.cash,
    this.notes = '',
  });

  final VehicleType vehicleType;
  final String description;
  final String phoneNumber;
  final PaymentMethod paymentMethod;
  final String notes;

  OrderFormData copyWith({
    VehicleType? vehicleType,
    String? description,
    String? phoneNumber,
    PaymentMethod? paymentMethod,
    String? notes,
  }) {
    return OrderFormData(
      vehicleType: vehicleType ?? this.vehicleType,
      description: description ?? this.description,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      notes: notes ?? this.notes,
    );
  }

  bool get isValid => phoneNumber.trim().length >= 10;
}

class ClientOrderState {
  const ClientOrderState({
    this.uiState = ClientHomeUIState.idle,
    this.pickupLocation,
    this.dropoffLocation,
    this.orderForm = const OrderFormData(),
    this.estimatedPrice,
    this.currentOrder,
    this.isLoading = false,
    this.error,
  });

  final ClientHomeUIState uiState;
  final MapLocation? pickupLocation;
  final MapLocation? dropoffLocation;
  final OrderFormData orderForm;
  final double? estimatedPrice;
  final Order? currentOrder;
  final bool isLoading;
  final String? error;

  ClientOrderState copyWith({
    ClientHomeUIState? uiState,
    MapLocation? pickupLocation,
    MapLocation? dropoffLocation,
    OrderFormData? orderForm,
    double? estimatedPrice,
    Order? currentOrder,
    bool clearCurrentOrder = false,
    bool? isLoading,
    String? error,
  }) {
    return ClientOrderState(
      uiState: uiState ?? this.uiState,
      pickupLocation: pickupLocation ?? this.pickupLocation,
      dropoffLocation: dropoffLocation ?? this.dropoffLocation,
      orderForm: orderForm ?? this.orderForm,
      estimatedPrice: estimatedPrice ?? this.estimatedPrice,
      currentOrder:
          clearCurrentOrder ? null : currentOrder ?? this.currentOrder,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  bool get canCreateOrder =>
      pickupLocation != null &&
      dropoffLocation != null &&
      orderForm.isValid &&
      estimatedPrice != null;
}

class ClientOrderNotifier extends StateNotifier<ClientOrderState> {
  ClientOrderNotifier(
    this._ref, {
    required this.orderRepository,
    required this.pricingService,
  }) : super(const ClientOrderState());

  final Ref _ref;
  final OrderRepository orderRepository;
  final PricingService pricingService;

  void startNewOrder() {
    state = const ClientOrderState(uiState: ClientHomeUIState.selectingPickup);
  }

  void selectPickupLocation(MapLocation location) {
    state = state.copyWith(
      pickupLocation: location,
      uiState: ClientHomeUIState.selectingDropoff,
      error: null,
    );
    _updatePrice();
  }

  void selectDropoffLocation(MapLocation location) {
    state = state.copyWith(
      dropoffLocation: location,
      uiState: ClientHomeUIState.fillingOrder,
      error: null,
    );
    _updatePrice();
  }

  void updateOrderForm(OrderFormData formData) {
    state = state.copyWith(orderForm: formData, error: null);
    _updatePrice();
  }

  Future<void> _updatePrice() async {
    final pickup = state.pickupLocation;
    final dropoff = state.dropoffLocation;
    if (pickup == null || dropoff == null) {
      state = state.copyWith(estimatedPrice: null);
      return;
    }

    try {
      final price = await pricingService.calculatePrice(
        pickup: pickup,
        dropoff: dropoff,
        vehicleType: state.orderForm.vehicleType,
        timeOfDay: DateTime.now(),
      );
      state = state.copyWith(estimatedPrice: price);
    } catch (_) {
      state = state.copyWith(estimatedPrice: 2500);
    }
  }

  Future<void> createOrder(String clientId) async {
    if (!state.canCreateOrder) return;
    state = state.copyWith(isLoading: true, error: null);

    try {
      final command = CreateOrderCommand(
        clientId: clientId,
        pickupLocation: state.pickupLocation!.toLocationModel(),
        dropoffLocation: state.dropoffLocation!.toLocationModel(),
        vehicleType: state.orderForm.vehicleType,
        distance: _calculateDistance(
          state.pickupLocation!,
          state.dropoffLocation!,
        ),
        estimatedPrice: state.estimatedPrice!,
        paymentMethod: state.orderForm.paymentMethod,
        notes: [
          state.orderForm.description.trim(),
          state.orderForm.notes.trim(),
        ].where((item) => item.isNotEmpty).join('. '),
      );

      await _ref.read(orderProvider.notifier).createOrder(command);
      final created = _ref.read(orderProvider).currentOrder;
      state = state.copyWith(
        currentOrder: created,
        uiState: ClientHomeUIState.searching,
        isLoading: false,
      );
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'Произошла ошибка. Попробуйте еще раз.',
      );
    }
  }

  Future<void> cancelOrder(String reason) async {
    final order = state.currentOrder;
    if (order == null) return;
    state = state.copyWith(isLoading: true, error: null);

    try {
      await orderRepository.cancelOrder(order.id, reason: reason);
      state = state.copyWith(
        uiState: ClientHomeUIState.completed,
        clearCurrentOrder: true,
        isLoading: false,
      );
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'Произошла ошибка. Попробуйте еще раз.',
      );
    }
  }

  void syncWithOrder(Order? order) {
    if (order == null) {
      if (state.uiState != ClientHomeUIState.idle) {
        state = const ClientOrderState();
      }
      return;
    }

    final newUIState = _mapOrderStatusToUIState(order.status);
    state = state.copyWith(
      currentOrder: order,
      uiState: newUIState,
      isLoading: false,
    );

    // Auto-transition back to idle after completed state
    if (newUIState == ClientHomeUIState.completed) {
      Future.delayed(const Duration(seconds: 3), () {
        if (state.uiState == ClientHomeUIState.completed) {
          state = const ClientOrderState();
        }
      });
    }
  }

  ClientHomeUIState _mapOrderStatusToUIState(OrderStatus status) {
    return switch (status) {
      OrderStatus.searching => ClientHomeUIState.searching,
      OrderStatus.assigned => ClientHomeUIState.driverAssigned,
      OrderStatus.onWay => ClientHomeUIState.driverArriving,
      OrderStatus.arrived => ClientHomeUIState.driverArriving,
      OrderStatus.evacuating => ClientHomeUIState.evacuating,
      OrderStatus.completed => ClientHomeUIState.completed,
      OrderStatus.cancelled => ClientHomeUIState.completed,
    };
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  double _calculateDistance(MapLocation from, MapLocation to) {
    const earthRadius = 6371.0;
    final lat1 = from.latitude * math.pi / 180;
    final lon1 = from.longitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final lon2 = to.longitude * math.pi / 180;
    final dLat = lat2 - lat1;
    final dLon = lon2 - lon1;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }
}

final clientOrderProvider =
    StateNotifierProvider<ClientOrderNotifier, ClientOrderState>((ref) {
  return ClientOrderNotifier(
    ref,
    orderRepository: ref.watch(orderRepositoryProvider),
    pricingService: ref.watch(pricingServiceProvider),
  );
});

final clientUIStateProvider = Provider<ClientHomeUIState>((ref) {
  return ref.watch(clientOrderProvider).uiState;
});

final estimatedPriceProvider = Provider<double?>((ref) {
  return ref.watch(clientOrderProvider).estimatedPrice;
});

final canCreateOrderProvider = Provider<bool>((ref) {
  return ref.watch(clientOrderProvider).canCreateOrder;
});
