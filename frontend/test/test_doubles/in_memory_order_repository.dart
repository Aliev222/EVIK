import 'dart:async';

import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/tariff.dart';
import 'package:tow_truck_frontend/features/order/domain/repositories/order_repository.dart';

class InMemoryOrderRepository implements OrderRepository {
  final Map<String, Order> _orders = <String, Order>{};
  final StreamController<List<Order>> _ordersController =
      StreamController<List<Order>>.broadcast();

  @override
  Future<Map<String, dynamic>> confirmPayment(String orderId) async {
    return <String, dynamic>{'status': 'succeeded'};
  }

  @override
  Future<void> updatePaymentMethod(String orderId, PaymentMethod method) async {
    final order = _orders[orderId];
    if (order != null) {
      _orders[orderId] = order.copyWith(paymentMethod: method);
      _emit();
    }
  }

  @override
  Future<List<Tariff>> getTariffs() async => const <Tariff>[];

  @override
  Future<Order> createOrder(CreateOrderCommand command) async {
    final id = 'order_${_orders.length + 1}';
    final order = Order(
      id: id,
      clientId: command.clientId,
      status: OrderStatus.searching,
      pickupLocation: command.pickupLocation,
      dropoffLocation: command.dropoffLocation,
      vehicleType: command.vehicleType,
      distance: command.distance,
      estimatedPrice: command.estimatedPrice,
      paymentMethod: command.paymentMethod,
      createdAt: DateTime.now(),
      notes: command.notes,
    );
    _orders[id] = order;
    _emit();
    return order;
  }

  @override
  Future<Order?> getOrder(String orderId) async => _orders[orderId];

  @override
  Future<Order?> getActiveOrder() async {
    for (final order in _orders.values) {
      if (order.status != OrderStatus.completed &&
          order.status != OrderStatus.cancelled) {
        return order;
      }
    }
    return null;
  }

  @override
  Future<List<Order>> getOrders() async => _orders.values.toList();

  @override
  Future<List<Order>> getOrdersByStatus(String status) async {
    return _orders.values.where((o) => o.status.name == status).toList();
  }

  @override
  Future<void> cancelOrder(String orderId, {String? reason}) async {
    final order = _orders[orderId];
    if (order == null) return;
    _orders[orderId] = order.copyWith(
      status: OrderStatus.cancelled,
      completedAt: DateTime.now(),
      notes: reason ?? order.notes,
    );
    _emit();
  }

  @override
  Future<void> acceptOrder(String orderId, String driverId) async {
    final order = _orders[orderId];
    if (order == null) return;
    _orders[orderId] = order.copyWith(
      driverId: driverId,
      status: OrderStatus.assigned,
      assignedAt: DateTime.now(),
    );
    _emit();
  }

  @override
  Future<void> updateOrderStatus(String orderId, OrderStatus status) async {
    final order = _orders[orderId];
    if (order == null) return;
    _orders[orderId] = order.copyWith(
      status: status,
      arrivedAt:
          status == OrderStatus.arrived ? DateTime.now() : order.arrivedAt,
      completedAt:
          status == OrderStatus.completed || status == OrderStatus.cancelled
              ? DateTime.now()
              : order.completedAt,
    );
    _emit();
  }

  @override
  Future<void> completeOrder(String orderId, double finalPrice) async {
    final order = _orders[orderId];
    if (order == null) return;
    _orders[orderId] = order.copyWith(
      status: OrderStatus.completed,
      finalPrice: finalPrice,
      completedAt: DateTime.now(),
    );
    _emit();
  }

  @override
  Future<void> finalizeOrder(String orderId, int finalPriceKopecks) async {
    final order = _orders[orderId];
    if (order == null) return;
    _orders[orderId] = order.copyWith(
      status: OrderStatus.awaitingPayment,
      finalPrice: finalPriceKopecks / 100,
    );
    _emit();
  }

  @override
  Stream<Order?> watchOrder(String orderId) {
    return _ordersController.stream
        .map((_) => _orders[orderId])
        .startWith(_orders[orderId]);
  }

  @override
  Stream<List<Order>> watchClientOrders(String clientId) {
    return _ordersController.stream
        .map(
            (_) => _orders.values.where((o) => o.clientId == clientId).toList())
        .startWith(
            _orders.values.where((o) => o.clientId == clientId).toList());
  }

  @override
  Stream<Order?> watchActiveOrderForClient(String clientId) {
    return _ordersController.stream
        .map((_) => _activeClientOrder(clientId))
        .startWith(_activeClientOrder(clientId));
  }

  @override
  Stream<List<Order>> watchAvailableOrders(
      double lat, double lng, double radiusKm) {
    return _ordersController.stream
        .map((_) => _orders.values
            .where((o) => o.status == OrderStatus.searching)
            .toList())
        .startWith(_orders.values
            .where((o) => o.status == OrderStatus.searching)
            .toList());
  }

  @override
  Stream<Order?> watchDriverCurrentOrder(String driverId) {
    return _ordersController.stream
        .map((_) => _activeDriverOrder(driverId))
        .startWith(_activeDriverOrder(driverId));
  }

  void _emit() {
    _ordersController.add(_orders.values.toList());
  }

  Order? _activeClientOrder(String clientId) {
    return _orders.values.cast<Order?>().firstWhere(
          (order) =>
              order != null &&
              order.clientId == clientId &&
              order.status != OrderStatus.completed &&
              order.status != OrderStatus.cancelled,
          orElse: () => null,
        );
  }

  Order? _activeDriverOrder(String driverId) {
    return _orders.values.cast<Order?>().firstWhere(
          (order) =>
              order != null &&
              order.driverId == driverId &&
              order.status != OrderStatus.completed &&
              order.status != OrderStatus.cancelled,
          orElse: () => null,
        );
  }
}

extension _StartWith<T> on Stream<T> {
  Stream<T> startWith(T value) async* {
    yield value;
    yield* this;
  }
}
