import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order_flow_state.dart';

class CreateOrderCommand {
  const CreateOrderCommand({
    required this.clientId,
    required this.pickupLocation,
    required this.dropoffLocation,
    required this.vehicleType,
    required this.distance,
    required this.estimatedPrice,
    required this.paymentMethod,
    this.towTruckType,
    this.notes,
    this.idempotencyKey,
  });

  final String clientId;
  final LocationModel pickupLocation;
  final LocationModel dropoffLocation;
  final VehicleType vehicleType;
  final double distance;
  final double estimatedPrice;
  final PaymentMethod paymentMethod;
  final TowTruckType? towTruckType;
  final String? notes;
  final String? idempotencyKey;
}

abstract class OrderRepository {
  /// Создать новый заказ
  Future<Order> createOrder(CreateOrderCommand command);

  /// Получить заказ по ID
  Future<Order?> getOrder(String orderId);

  /// Получить активный (не терминальный) заказ текущего пользователя.
  /// Возвращает null, если активного заказа нет.
  /// Роль (клиент/водитель) определяется бэкендом по JWT.
  Future<Order?> getActiveOrder();

  /// Отменить заказ
  Future<void> cancelOrder(String orderId, {String? reason});

  /// Принять заказ водителем
  Future<void> acceptOrder(String orderId, String driverId);

  /// Обновить статус заказа
  Future<void> updateOrderStatus(String orderId, OrderStatus status);

  /// Завершить заказ с финальной ценой
  Future<void> completeOrder(String orderId, double finalPrice);

  /// Финализировать заказ (водитель) — переводит в статус ожидания оплаты
  /// [finalPriceKopecks] — финальная цена в копейках
  Future<void> finalizeOrder(String orderId, int finalPriceKopecks);

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

  /// Получить историю заказов пользователя
  Future<List<Order>> getOrders();

  /// Получить заказы по статусу (для истории водителя)
  Future<List<Order>> getOrdersByStatus(String status);

  /// Подтвердить оплату заказа
  Future<Map<String, dynamic>> confirmPayment(String orderId);

  /// Обновить способ оплаты заказа
  Future<void> updatePaymentMethod(String orderId, PaymentMethod method);
}
