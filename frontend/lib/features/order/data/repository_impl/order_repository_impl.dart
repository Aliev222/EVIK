import 'dart:async';

import 'package:tow_truck_frontend/core/network/api_client.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/features/order/domain/repositories/order_repository.dart';
import 'package:tow_truck_frontend/features/order/data/datasource/order_remote_datasource.dart';
import 'package:tow_truck_frontend/features/order/data/dto/order_dto.dart';

class OrderRepositoryImpl implements OrderRepository {
  OrderRepositoryImpl({required this.remote});

  final OrderRemoteDataSource remote;
  final Map<String, Order> _orders = <String, Order>{};
  final Map<String, StreamController<OrderState>> _controllers =
      <String, StreamController<OrderState>>{};

  @override
  Future<Order> createOrder(CreateOrderCommand command) async {
    final dto = await remote.createOrder(
      userId: command.userId,
      pickupLat: command.pickup.lat,
      pickupLng: command.pickup.lng,
      dropoffLat: command.dropoff.lat,
      dropoffLng: command.dropoff.lng,
    );
    final order = dto.toDomain();
    _orders[order.id] = order;
    _controllerFor(order.id).add(order.state);
    return order;
  }

  @override
  Future<Order> getOrder(String orderId) async {
    final dto = await remote.getOrder(orderId);
    final order = dto.toDomain();
    _orders[order.id] = order;
    _controllerFor(order.id).add(order.state);
    return order;
  }

  @override
  Future<Order> cancelOrder(String orderId, {String? reason}) async {
    final dto = await remote.cancelOrder(orderId, reason: reason);
    final cancelled = dto.toDomain();
    _orders[cancelled.id] = cancelled;
    _controllerFor(orderId).add(cancelled.state);
    return cancelled;
  }

  @override
  Stream<OrderState> watchOrderState(String orderId) {
    return _controllerFor(orderId).stream;
  }

  StreamController<OrderState> _controllerFor(String orderId) {
    return _controllers.putIfAbsent(
      orderId,
      () => StreamController<OrderState>.broadcast(),
    );
  }
}

class HttpOrderRemoteDataSource implements OrderRemoteDataSource {
  const HttpOrderRemoteDataSource({
    required this.apiClient,
    this.accessToken,
  });

  final ApiClient apiClient;
  final String? accessToken;

  Map<String, String>? get _authHeaders {
    final token = accessToken;
    if (token == null || token.isEmpty) {
      return null;
    }
    return <String, String>{'Authorization': 'Bearer $token'};
  }

  @override
  Future<OrderDto> createOrder({
    required String userId,
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
  }) async {
    final json = await apiClient.post(
      '/api/v1/orders',
      {
        'user_id': userId,
        'pickup_lat': pickupLat,
        'pickup_lng': pickupLng,
        'dropoff_lat': dropoffLat,
        'dropoff_lng': dropoffLng,
        'auto_dispatch': true,
      },
      headers: _authHeaders,
    );
    return OrderDto.fromJson(json['order'] as Map<String, dynamic>);
  }

  @override
  Future<OrderDto> getOrder(String orderId) async {
    final json = await apiClient.get(
      '/api/v1/orders/$orderId',
      headers: _authHeaders,
    );
    return OrderDto.fromJson(json['order'] as Map<String, dynamic>);
  }

  @override
  Future<OrderDto> cancelOrder(String orderId, {String? reason}) async {
    final payload = <String, dynamic>{};
    if (reason != null && reason.isNotEmpty) {
      payload['reason'] = reason;
    }
    final json = await apiClient.post(
      '/api/v1/orders/$orderId/cancel',
      payload,
      headers: _authHeaders,
    );
    return OrderDto.fromJson(json['order'] as Map<String, dynamic>);
  }
}
