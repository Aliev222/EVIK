import '../../../core/services/api_client.dart';
import '../domain/entities/order.dart';

class CreateOrderRequest {
  const CreateOrderRequest({
    required this.pickup,
    required this.dropoff,
    required this.vehicleType,
    required this.paymentMethod,
    required this.description,
    this.notes = '',
  });

  final LocationModel pickup;
  final LocationModel dropoff;
  final VehicleType vehicleType;
  final PaymentMethod paymentMethod;
  final String description;
  final String notes;

  Map<String, dynamic> toJson() => {
    'pickup': {
      'lat': pickup.lat,
      'lng': pickup.lng,
      'address': pickup.address,
    },
    'dropoff': {
      'lat': dropoff.lat,
      'lng': dropoff.lng,
      'address': dropoff.address,
    },
    'vehicle_type': vehicleType.name,
    'payment_method': paymentMethod.name,
    'description': description,
    'notes': notes,
  };
}

class UpdateOrderStatusRequest {
  const UpdateOrderStatusRequest({
    required this.status,
    this.notes,
  });

  final OrderStatus status;
  final String? notes;

  Map<String, dynamic> toJson() => {
    'status': status.name,
    if (notes != null) 'notes': notes,
  };
}

class CancelOrderRequest {
  const CancelOrderRequest({
    required this.reason,
  });

  final String reason;

  Map<String, dynamic> toJson() => {
    'reason': reason,
  };
}

class OrdersApiClient {
  OrdersApiClient({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  /// Create a new order
  Future<Order> createOrder(CreateOrderRequest request) async {
    try {
      final response = await _apiClient.post('/orders', request.toJson());
      return Order.fromMap(response);
    } catch (e) {
      throw OrderApiException('Failed to create order', e);
    }
  }

  /// Get order by ID
  Future<Order> getOrder(String orderId) async {
    try {
      final response = await _apiClient.get('/orders/$orderId');
      return Order.fromMap(response);
    } catch (e) {
      throw OrderApiException('Failed to get order', e);
    }
  }

  /// Get user's orders with optional status filter
  Future<List<Order>> getUserOrders({
    String? userId,
    OrderStatus? status,
    int? limit,
    int? offset,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (userId != null) queryParams['user_id'] = userId;
      if (status != null) queryParams['status'] = status.name;
      if (limit != null) queryParams['limit'] = limit.toString();
      if (offset != null) queryParams['offset'] = offset.toString();

      final queryString = queryParams.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');

      final endpoint = queryString.isEmpty ? '/orders' : '/orders?$queryString';
      final response = await _apiClient.get(endpoint);

      final orders = response['orders'] as List<dynamic>;
      return orders.map((json) => Order.fromMap(json as Map<String, dynamic>)).toList();
    } catch (e) {
      throw OrderApiException('Failed to get user orders', e);
    }
  }

  /// Update order status
  Future<Order> updateOrderStatus(String orderId, OrderStatus status, {String? notes}) async {
    try {
      final request = UpdateOrderStatusRequest(status: status, notes: notes);
      final response = await _apiClient.post('/orders/$orderId/status', request.toJson());
      return Order.fromMap(response);
    } catch (e) {
      throw OrderApiException('Failed to update order status', e);
    }
  }

  /// Accept order (for drivers)
  Future<Order> acceptOrder(String orderId) async {
    try {
      final response = await _apiClient.post('/orders/$orderId/accept', {});
      return Order.fromMap(response);
    } catch (e) {
      throw OrderApiException('Failed to accept order', e);
    }
  }

  /// Cancel order
  Future<Order> cancelOrder(String orderId, String reason) async {
    try {
      final request = CancelOrderRequest(reason: reason);
      final response = await _apiClient.post('/orders/$orderId/cancel', request.toJson());
      return Order.fromMap(response);
    } catch (e) {
      throw OrderApiException('Failed to cancel order', e);
    }
  }

  /// Get available orders for drivers in area
  Future<List<Order>> getAvailableOrders({
    required double lat,
    required double lng,
    double radius = 10.0, // km
    int? limit,
  }) async {
    try {
      final queryParams = {
        'lat': lat.toString(),
        'lng': lng.toString(),
        'radius': radius.toString(),
        if (limit != null) 'limit': limit.toString(),
      };

      final queryString = queryParams.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');

      final response = await _apiClient.get('/orders/available?$queryString');

      final orders = response['orders'] as List<dynamic>;
      return orders.map((json) => Order.fromMap(json as Map<String, dynamic>)).toList();
    } catch (e) {
      throw OrderApiException('Failed to get available orders', e);
    }
  }
}

class OrderApiException implements Exception {
  final String message;
  final dynamic originalError;

  OrderApiException(this.message, this.originalError);

  @override
  String toString() => 'OrderApiException: $message${originalError != null ? ' ($originalError)' : ''}';
}