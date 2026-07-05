import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tow_truck_frontend/core/network/api_client.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order_flow_state.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/tariff.dart';
import 'package:tow_truck_frontend/features/order/domain/repositories/order_repository.dart';

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
      'auto_dispatch': false,
      'is_mock': command.pickupLocation.isMocked || command.dropoffLocation.isMocked,
    };

    // Add tow truck type if specified
    if (command.towTruckType != null) {
      body['tow_truck_type'] = command.towTruckType!.name;
    }

    // Add human-readable addresses if available
    if (command.pickupLocation.address.isNotEmpty) {
      body['pickup_address'] = command.pickupLocation.address;
    }
    if (command.dropoffLocation.address.isNotEmpty) {
      body['dropoff_address'] = command.dropoffLocation.address;
    }

    debugPrint('Token: ${_accessTokenProvider?.call() ?? _accessToken}');
    final response = await _apiClient.post(
      '/api/v1/orders',
      body,
      headers: _authHeaders,
    );
    return Order.fromMap(response['order'] as Map<String, dynamic>);
  }

  Future<OrderPriceQuote> calculatePrice({
    required LocationModel pickup,
    required LocationModel dropoff,
    required TowTruckType towTruckType,
  }) async {
    final response = await _apiClient.post(
      '/api/v1/pricing/calculate',
      <String, dynamic>{
        'pickup_lat': pickup.lat,
        'pickup_lng': pickup.lng,
        'dropoff_lat': dropoff.lat,
        'dropoff_lng': dropoff.lng,
        'tow_truck_type': towTruckType.name,
      },
      headers: _authHeaders,
    );
    return OrderPriceQuote.fromJson(response);
  }

  Future<OrderPayment> createOrderPayment(
    String orderId,
    PaymentMethod paymentMethod,
  ) async {
    final response = await _apiClient.post(
      '/api/v1/orders/$orderId/payments',
      <String, dynamic>{'payment_method': paymentMethod.name},
      headers: _authHeaders,
    );
    return OrderPayment.fromJson(response['payment'] as Map<String, dynamic>);
  }

  Future<OrderPayment> getOrderPaymentStatus(String orderId) async {
    final response = await _apiClient.get(
      '/api/v1/orders/$orderId/payment-status',
      headers: _authHeaders,
    );
    return OrderPayment.fromJson(response['payment'] as Map<String, dynamic>);
  }

  Future<OrderReceipt> getOrderReceipt(String orderId) async {
    final response = await _apiClient.get(
      '/api/v1/orders/$orderId/receipt',
      headers: _authHeaders,
    );
    return OrderReceipt.fromJson(response);
  }

  @override
  Future<List<Tariff>> getTariffs() async {
    final response = await _apiClient.get(
      '/api/v1/pricing/tariffs',
      headers: _authHeaders,
    );
    final raw = response['tariffs'] as List<dynamic>? ?? const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(Tariff.fromJson)
        .whereType<Tariff>()
        .toList();
  }

  @override
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
  Future<Order?> getActiveOrder() async {
    final response = await _apiClient.get(
      '/api/v1/orders/active',
      headers: _authHeaders,
    );
    final raw = response['order'];
    if (raw == null) return null;
    return Order.fromMap(raw as Map<String, dynamic>);
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
  Future<void> finalizeOrder(String orderId, int finalPriceKopecks) async {
    await _apiClient.post(
      '/api/v1/orders/$orderId/finalize',
      <String, dynamic>{'final_price': finalPriceKopecks},
      headers: _authHeaders,
    );
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

  @override
  Future<Map<String, dynamic>> confirmPayment(String orderId) async {
    final response = await _apiClient.post(
      '/api/v1/orders/$orderId/confirm-payment',
      const <String, dynamic>{},
      headers: _authHeaders,
    );
    return response;
  }

  @override
  Future<void> updatePaymentMethod(String orderId, PaymentMethod method) async {
    await _apiClient.patch(
      '/api/v1/orders/$orderId/payment-method',
      <String, dynamic>{'payment_method': method.name},
      headers: _authHeaders,
    );
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
      OrderStatus.awaitingPayment => 'awaiting_payment',
      OrderStatus.completed => 'completed',
      OrderStatus.cancelled => 'cancelled',
    };
  }
}

class OrderPriceQuote {
  const OrderPriceQuote({
    required this.distanceKm,
    required this.totalPrice,
    required this.currency,
  });

  final double distanceKm;
  final int totalPrice;
  final String currency;

  factory OrderPriceQuote.fromJson(Map<String, dynamic> json) {
    return OrderPriceQuote(
      distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0,
      totalPrice: (json['total_price'] as num?)?.toInt() ?? 0,
      currency: json['currency']?.toString() ?? 'RUB',
    );
  }
}

class OrderPayment {
  const OrderPayment({
    required this.id,
    required this.orderId,
    required this.paymentMethod,
    required this.amount,
    required this.currency,
    required this.status,
    this.confirmationUrl,
    this.createdAt,
    this.paidAt,
  });

  final String id;
  final String orderId;
  final PaymentMethod paymentMethod;
  final int amount;
  final String currency;
  final String status;
  final String? confirmationUrl;
  final DateTime? createdAt;
  final DateTime? paidAt;

  bool get isPending => status == 'pending' || status == 'waiting_for_capture';
  bool get isSucceeded => status == 'succeeded' || status == 'paid';
  bool get isFailed => status == 'failed' || status == 'canceled';

  factory OrderPayment.fromJson(Map<String, dynamic> json) {
    return OrderPayment(
      id: json['id']?.toString() ?? '',
      orderId: json['order_id']?.toString() ?? '',
      paymentMethod: _parsePaymentMethod(json['payment_method']?.toString()),
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      currency: json['currency']?.toString() ?? 'RUB',
      status: json['status']?.toString() ?? 'pending',
      confirmationUrl: json['confirmation_url']?.toString(),
      createdAt: _parseDate(json['created_at']),
      paidAt: _parseDate(json['paid_at']),
    );
  }

  static PaymentMethod _parsePaymentMethod(String? value) {
    return value == 'card' ? PaymentMethod.card : PaymentMethod.cash;
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}

class OrderReceipt {
  const OrderReceipt({
    required this.orderId,
    this.paymentId = '',
    required this.priceTotal,
    required this.currency,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.commissionAmount,
    required this.driverAmount,
    this.createdAt,
    this.completedAt,
    this.driverId,
    this.driverName,
    this.driverPhone,
  });

  final String orderId;
  final String paymentId;
  final int priceTotal;
  final String currency;
  final String paymentMethod;
  final String paymentStatus;
  final int commissionAmount;
  final int driverAmount;
  final DateTime? createdAt;
  final DateTime? completedAt;
  final String? driverId;
  final String? driverName;
  final String? driverPhone;

  factory OrderReceipt.fromJson(Map<String, dynamic> json) {
    return OrderReceipt(
      orderId: json['order_id']?.toString() ?? '',
      paymentId: json['payment_id']?.toString() ?? '',
      priceTotal: (json['price_total'] as num?)?.toInt() ??
          (json['amount'] as num?)?.toInt() ??
          0,
      currency: json['currency']?.toString() ?? 'RUB',
      paymentMethod: json['payment_method']?.toString() ?? 'cash',
      paymentStatus: json['payment_status']?.toString() ??
          json['status']?.toString() ??
          '',
      commissionAmount: (json['commission_amount'] as num?)?.toInt() ??
          (json['commission'] as num?)?.toInt() ??
          0,
      driverAmount: (json['driver_amount'] as num?)?.toInt() ?? 0,
      createdAt: OrderPayment._parseDate(json['created_at']),
      completedAt: OrderPayment._parseDate(json['completed_at']) ??
          OrderPayment._parseDate(json['paid_at']),
      driverId: json['driver_id']?.toString(),
      driverName: json['driver_name']?.toString(),
      driverPhone: json['driver_phone']?.toString(),
    );
  }
}
