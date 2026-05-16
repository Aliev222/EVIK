import 'package:tow_truck_frontend/features/order/data/dto/order_dto.dart';

abstract class OrderRemoteDataSource {
  Future<OrderDto> createOrder({
    required String userId,
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
  });

  Future<OrderDto> getOrder(String orderId);

  Future<OrderDto> cancelOrder(String orderId, {String? reason});
}
