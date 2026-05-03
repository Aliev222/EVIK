import '../domain/entities/order.dart';
import 'orders_api_client.dart';

class MockOrdersService {
  static const _mockOrders = [
    // Mock completed order
    {
      'id': 'order_001',
      'user_id': 'user_123',
      'driver_id': 'driver_456',
      'status': 'completed',
      'pickup': {'lat': 55.7558, 'lng': 37.6176, 'address': 'Красная площадь'},
      'dropoff': {'lat': 55.7335, 'lng': 37.5904, 'address': 'Воробьевы горы'},
      'vehicle_type': 'light',
      'payment_method': 'card',
      'price': 1250.0,
      'description': 'Не заводится двигатель',
      'notes': 'Быстрая эвакуация, спасибо!',
      'created_at': '2024-12-25T14:00:00Z',
      'updated_at': '2024-12-25T15:30:00Z',
    },
    // Mock active order
    {
      'id': 'order_002',
      'user_id': 'user_123',
      'driver_id': 'driver_789',
      'status': 'searching',
      'pickup': {'lat': 55.7889, 'lng': 37.6333, 'address': 'Тверская улица'},
      'dropoff': {'lat': 55.7422, 'lng': 37.6156, 'address': 'Лубянка'},
      'vehicle_type': 'suv',
      'payment_method': 'cash',
      'price': 800.0,
      'description': 'Спущено колесо',
      'notes': '',
      'created_at': '2024-12-25T16:00:00Z',
      'updated_at': '2024-12-25T16:05:00Z',
    }
  ];

  static int _nextOrderId = 3;

  // Simulate create order API call
  Future<Order> createOrder(CreateOrderRequest request) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 1200));

    final orderId = 'order_${_nextOrderId.toString().padLeft(3, '0')}';
    _nextOrderId++;

    final orderData = {
      'id': orderId,
      'user_id': 'user_123', // Current user
      'driver_id': null,
      'status': 'searching',
      'pickup': {
        'lat': request.pickup.lat,
        'lng': request.pickup.lng,
        'address': request.pickup.address,
      },
      'dropoff': {
        'lat': request.dropoff.lat,
        'lng': request.dropoff.lng,
        'address': request.dropoff.address,
      },
      'vehicle_type': request.vehicleType.name,
      'payment_method': request.paymentMethod.name,
      'price': _calculatePrice(request),
      'description': request.description,
      'notes': request.notes,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };

    return Order.fromMap(orderData);
  }

  // Simulate get order API call
  Future<Order> getOrder(String orderId) async {
    await Future.delayed(const Duration(milliseconds: 400));

    final orderData = _mockOrders.firstWhere(
      (order) => order['id'] == orderId,
      orElse: () => throw MockOrderException('Order not found', 404),
    );

    return Order.fromMap(Map<String, dynamic>.from(orderData));
  }

  // Simulate get user orders API call
  Future<List<Order>> getUserOrders({
    String? userId,
    OrderStatus? status,
    int? limit,
    int? offset,
  }) async {
    await Future.delayed(const Duration(milliseconds: 600));

    var orders = _mockOrders.where((order) {
      if (userId != null && order['user_id'] != userId) return false;
      if (status != null && order['status'] != status.name) return false;
      return true;
    }).toList();

    if (offset != null && offset > 0) {
      orders = orders.skip(offset).toList();
    }

    if (limit != null && limit > 0) {
      orders = orders.take(limit).toList();
    }

    return orders.map((orderData) => Order.fromMap(Map<String, dynamic>.from(orderData))).toList();
  }

  // Simulate update order status API call
  Future<Order> updateOrderStatus(String orderId, OrderStatus status, {String? notes}) async {
    await Future.delayed(const Duration(milliseconds: 500));

    final orderIndex = _mockOrders.indexWhere((order) => order['id'] == orderId);
    if (orderIndex == -1) {
      throw MockOrderException('Order not found', 404);
    }

    final orderData = Map<String, dynamic>.from(_mockOrders[orderIndex]);
    orderData['status'] = status.name;
    orderData['updated_at'] = DateTime.now().toIso8601String();

    if (notes != null) {
      orderData['notes'] = notes;
    }

    // Simulate status-specific updates
    switch (status) {
      case OrderStatus.assigned:
        orderData['driver_id'] = 'driver_${DateTime.now().millisecondsSinceEpoch}';
        break;
      case OrderStatus.completed:
        orderData['completed_at'] = DateTime.now().toIso8601String();
        break;
      case OrderStatus.cancelled:
        orderData['cancelled_at'] = DateTime.now().toIso8601String();
        break;
      default:
        break;
    }

    return Order.fromMap(orderData);
  }

  // Simulate accept order API call
  Future<Order> acceptOrder(String orderId) async {
    await Future.delayed(const Duration(milliseconds: 700));

    return updateOrderStatus(orderId, OrderStatus.assigned);
  }

  // Simulate cancel order API call
  Future<Order> cancelOrder(String orderId, String reason) async {
    await Future.delayed(const Duration(milliseconds: 600));

    final orderData = await getOrder(orderId);

    // Simulate cancellation with reason in notes
    return updateOrderStatus(orderId, OrderStatus.cancelled, notes: 'Отменен: $reason');
  }

  // Simulate get available orders for drivers
  Future<List<Order>> getAvailableOrders({
    required double lat,
    required double lng,
    double radius = 10.0,
    int? limit,
  }) async {
    await Future.delayed(const Duration(milliseconds: 800));

    // Filter orders by status and simulate radius check
    final availableOrders = _mockOrders.where((order) {
      if (order['status'] != 'searching') return false;
      if (order['driver_id'] != null) return false;

      // Simple radius check simulation
      final pickupLat = order['pickup']['lat'] as double;
      final pickupLng = order['pickup']['lng'] as double;
      final distance = _calculateDistance(lat, lng, pickupLat, pickupLng);

      return distance <= radius;
    }).toList();

    var orders = availableOrders;
    if (limit != null && limit > 0) {
      orders = orders.take(limit).toList();
    }

    return orders.map((orderData) => Order.fromMap(Map<String, dynamic>.from(orderData))).toList();
  }

  // Helper method to calculate estimated price
  static double _calculatePrice(CreateOrderRequest request) {
    const baseFare = 500.0;
    const perKmRate = 50.0;

    final distance = _calculateDistance(
      request.pickup.lat, request.pickup.lng,
      request.dropoff.lat, request.dropoff.lng,
    );

    var price = baseFare + (distance * perKmRate);

    // Vehicle type multiplier
    switch (request.vehicleType) {
      case VehicleType.light:
        price *= 1.0;
        break;
      case VehicleType.suv:
        price *= 1.3;
        break;
      case VehicleType.minibus:
        price *= 1.5;
        break;
      case VehicleType.truck:
        price *= 2.0;
        break;
    }

    return price.roundToDouble();
  }

  // Helper method to calculate distance between two points (simplified)
  static double _calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    // Simplified distance calculation (not accurate, for demo purposes)
    final deltaLat = lat2 - lat1;
    final deltaLng = lng2 - lng1;
    return (deltaLat.abs() + deltaLng.abs()) * 100; // Rough km approximation
  }
}

class MockOrderException implements Exception {
  final String message;
  final int statusCode;

  MockOrderException(this.message, this.statusCode);

  @override
  String toString() => 'MockOrderException($statusCode): $message';
}