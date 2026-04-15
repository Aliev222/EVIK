import 'dart:async';

import '../../../../core/network/api_client.dart';
import '../../domain/entities/order.dart';
import '../../domain/repositories/order_repository.dart';
import '../datasource/order_remote_datasource.dart';
import '../dto/order_dto.dart';

class OrderRepositoryImpl implements OrderRepository {
  OrderRepositoryImpl({required this.remote});

  final OrderRemoteDataSource remote;
  final Map<String, Order> _orders = <String, Order>{};
  final Map<String, StreamController<OrderState>> _controllers = <String, StreamController<OrderState>>{};

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
  Future<Order> cancelOrder(String orderId) async {
    final current = _orders[orderId];
    if (current == null) {
      // TODO: Replace with real cancel API request and domain error mapping.
      final fallback = Order(
        id: orderId,
        userId: 'unknown',
        pickup: const Coordinate(lat: 0, lng: 0),
        dropoff: const Coordinate(lat: 0, lng: 0),
        state: OrderState.cancelled,
      );
      _orders[orderId] = fallback;
      _controllerFor(orderId).add(fallback.state);
      return fallback;
    }
    final cancelled = current.copyWith(state: OrderState.cancelled);
    _orders[orderId] = cancelled;
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
  const HttpOrderRemoteDataSource({required this.apiClient});

  final ApiClient apiClient;

  @override
  Future<OrderDto> createOrder({
    required String userId,
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
  }) async {
    final json = await apiClient.post('/api/v1/orders', {
      'user_id': userId,
      'pickup_lat': pickupLat,
      'pickup_lng': pickupLng,
      'dropoff_lat': dropoffLat,
      'dropoff_lng': dropoffLng,
      'auto_dispatch': true,
    });
    return OrderDto.fromJson(json['order'] as Map<String, dynamic>);
  }
}
