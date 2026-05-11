import 'dart:async';

import '../../../../core/network/api_client.dart';
import '../../domain/entities/order.dart';
import '../../domain/repositories/order_repository.dart';

class HttpOrderRepository implements OrderRepository {
  const HttpOrderRepository({
    required ApiClient apiClient,
    required String? accessToken,
    String? Function()? accessTokenProvider,
  })  : _apiClient = apiClient,
        _accessToken = accessToken,
        _accessTokenProvider = accessTokenProvider;

  final ApiClient _apiClient;
  final String? _accessToken;
  final String? Function()? _accessTokenProvider;

  Map<String, String>? get _authHeaders {
    final token = _accessTokenProvider?.call() ?? _accessToken;
    if (token == null || token.isEmpty) {
      return null;
    }
    return <String, String>{'Authorization': 'Bearer $token'};
  }

  @override
  Future<Order> createOrder(CreateOrderCommand command) async {
    final body = <String, dynamic>{
      'pickup_lat': command.pickupLocation.lat,
      'pickup_lng': command.pickupLocation.lng,
      'dropoff_lat': command.dropoffLocation.lat,
      'dropoff_lng': command.dropoffLocation.lng,
      'payment_method': command.paymentMethod.name,
      'auto_dispatch': true,
    };

    // Add tow truck type if specified
    if (command.towTruckType != null) {
      body['tow_truck_type'] = command.towTruckType!.name;
    }

    final response = await _apiClient.post(
      '/api/v1/orders',
      body,
      headers: _authHeaders,
    );
    final order = Order.fromMap(response['order'] as Map<String, dynamic>);
    await _apiClient.post(
      '/api/v1/orders/${order.id}/payments',
      <String, dynamic>{'payment_method': command.paymentMethod.name},
      headers: _authHeaders,
    );
    return order;
  }

  Future<List<Order>> getOrders() async {
    final response = await _apiClient.get(
      '/api/v1/orders',
      headers: _authHeaders,
    );
    final ordersData = response['orders'] as List<dynamic>? ?? const [];
    return ordersData
        .map((data) => Order.fromMap(data as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Order?> getOrder(String orderId) async {
    final response = await _apiClient.get(
      '/api/v1/orders/$orderId',
      headers: _authHeaders,
    );
    return Order.fromMap(response['order'] as Map<String, dynamic>);
  }

  @override
  Future<void> cancelOrder(String orderId, {String? reason}) async {
    await _apiClient.post(
      '/api/v1/orders/$orderId/cancel',
      <String, dynamic>{
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
      headers: _authHeaders,
    );
  }

  @override
  Future<void> acceptOrder(String orderId, String driverId) async {
    await _apiClient.post(
      '/api/v1/orders/$orderId/accept',
      const <String, dynamic>{},
      headers: _authHeaders,
    );
  }

  @override
  Future<void> updateOrderStatus(String orderId, OrderStatus status) async {
    if (status == OrderStatus.onWay) {
      return;
    }
    await _apiClient.post(
      '/api/v1/orders/$orderId/status',
      <String, dynamic>{'status': _backendStatus(status)},
      headers: _authHeaders,
    );
  }

  @override
  Future<void> completeOrder(String orderId, double finalPrice) {
    return updateOrderStatus(orderId, OrderStatus.completed);
  }

  @override
  Stream<Order?> watchOrder(String orderId) async* {
    while (true) {
      try {
        yield await getOrder(orderId);
      } catch (_) {
        yield null;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  @override
  Stream<List<Order>> watchClientOrders(String clientId) {
    return _watchOrders().map(
      (orders) => orders.where((order) => order.clientId == clientId).toList(),
    );
  }

  @override
  Stream<Order?> watchActiveOrderForClient(String clientId) {
    return watchClientOrders(clientId).map((orders) {
      for (final order in orders) {
        if (!_isTerminal(order.status)) {
          return order;
        }
      }
      return null;
    });
  }

  @override
  Stream<List<Order>> watchAvailableOrders(
    double lat,
    double lng,
    double radiusKm,
  ) {
    return _watchOrders().map(
      (orders) => orders
          .where((order) => order.status == OrderStatus.searching)
          .toList(),
    );
  }

  @override
  Stream<Order?> watchDriverCurrentOrder(String driverId) {
    return _watchOrders().map((orders) {
      for (final order in orders) {
        if (order.driverId == driverId && !_isTerminal(order.status)) {
          return order;
        }
      }
      return null;
    });
  }

  Stream<List<Order>> _watchOrders() async* {
    while (true) {
      try {
        yield await getOrders();
      } catch (_) {
        yield const <Order>[];
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  static bool _isTerminal(OrderStatus status) {
    return switch (status) {
      OrderStatus.completed || OrderStatus.cancelled => true,
      _ => false,
    };
  }

  static String _backendStatus(OrderStatus status) {
    return switch (status) {
      OrderStatus.searching => 'searching',
      OrderStatus.assigned => 'accepted',
      OrderStatus.onWay => 'in_progress',
      OrderStatus.arrived => 'arrived',
      OrderStatus.evacuating => 'in_progress',
      OrderStatus.completed => 'completed',
      OrderStatus.cancelled => 'cancelled',
    };
  }
}
