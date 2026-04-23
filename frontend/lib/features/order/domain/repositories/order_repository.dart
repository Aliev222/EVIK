import '../entities/order.dart';

class CreateOrderCommand {
  const CreateOrderCommand({
    required this.userId,
    required this.pickup,
    required this.dropoff,
  });

  final String userId;
  final Coordinate pickup;
  final Coordinate dropoff;
}

abstract class OrderRepository {
  Future<Order> createOrder(CreateOrderCommand command);
  Future<Order> getOrder(String orderId);
  Future<Order> cancelOrder(String orderId, {String? reason});
  Stream<OrderState> watchOrderState(String orderId);
}
