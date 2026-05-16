import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';

class OrderStatusService {
  Future<String?> uploadDeliveryPhoto(String orderId, String? photoPath) async {
    if (photoPath == null || photoPath.trim().isEmpty) {
      return null;
    }
    return photoPath;
  }

  double calculateFinalPrice(Order order) {
    return order.finalPrice ?? order.estimatedPrice;
  }
}

class OrderStatusException implements Exception {
  const OrderStatusException(this.message);

  final String message;

  @override
  String toString() => message;
}
