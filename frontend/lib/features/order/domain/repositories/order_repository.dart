import '../entities/order.dart';

class CreateOrderCommand {
  const CreateOrderCommand({
    required this.clientId,
    required this.pickupLocation,
    required this.dropoffLocation,
    required this.vehicleType,
    required this.distance,
    required this.estimatedPrice,
    required this.paymentMethod,
    this.notes,
  });

  final String clientId;
  final LocationModel pickupLocation;
  final LocationModel dropoffLocation;
  final VehicleType vehicleType;
  final double distance;
  final double estimatedPrice;
  final PaymentMethod paymentMethod;
  final String? notes;
}

abstract class OrderRepository {
  /// Создать новый заказ
  Future<Order> createOrder(CreateOrderCommand command);

  /// Получить заказ по ID
  Future<Order?> getOrder(String orderId);

  /// Отменить заказ
  Future<void> cancelOrder(String orderId, {String? reason});

  /// Принять заказ водителем
  Future<void> acceptOrder(String orderId, String driverId);

  /// Обновить статус заказа
  Future<void> updateOrderStatus(String orderId, OrderStatus status);

  /// Завершить заказ с финальной ценой
  Future<void> completeOrder(String orderId, double finalPrice);

  /// Слушать изменения заказа в реальном времени
  Stream<Order?> watchOrder(String orderId);

  /// Получить активные заказы для клиента
  Stream<List<Order>> watchClientOrders(String clientId);

  /// Получить активный заказ клиента (не завершенный и не отмененный)
  Stream<Order?> watchActiveOrderForClient(String clientId);

  /// Получить заказы для водителей в радиусе
  Stream<List<Order>> watchAvailableOrders(
      double lat, double lng, double radiusKm);

  /// Получить текущий заказ водителя
  Stream<Order?> watchDriverCurrentOrder(String driverId);
}
