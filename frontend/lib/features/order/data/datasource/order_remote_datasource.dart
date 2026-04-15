import '../dto/order_dto.dart';

abstract class OrderRemoteDataSource {
  Future<OrderDto> createOrder({
    required String userId,
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
  });
}
