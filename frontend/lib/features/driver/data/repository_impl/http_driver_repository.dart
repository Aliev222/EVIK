import 'dart:async';

import '../../../../core/network/api_client.dart';
import '../../../order/domain/entities/order.dart';
import '../../domain/entities/active_order.dart';
import '../../domain/entities/available_order.dart';
import '../../domain/entities/driver.dart';
import '../repository/driver_repository.dart';

class HttpDriverRepository implements DriverRepository {
  const HttpDriverRepository({
    required ApiClient apiClient,
    required String? accessToken,
  })  : _apiClient = apiClient,
        _accessToken = accessToken;

  final ApiClient _apiClient;
  final String? _accessToken;

  Map<String, String>? get _authHeaders {
    final token = _accessToken;
    if (token == null || token.isEmpty) return null;
    return <String, String>{'Authorization': 'Bearer $token'};
  }

  Future<Driver> getDriverProfile(String driverId) async {
    final response = await _apiClient.get(
      '/api/v1/drivers/$driverId',
      headers: _authHeaders,
    );
    return Driver.fromMap(response['driver'] as Map<String, dynamic>);
  }

  @override
  Future<Driver?> getDriver(String userId) async {
    try {
      return await getDriverProfile(userId);
    } on ApiClientException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<void> createDriver(Driver driver) async {
    await updateDriverStatus(
      driverId: driver.userId,
      isOnline: driver.isOnline,
      lat: driver.currentLocation?.lat ?? 55.7558,
      lng: driver.currentLocation?.lng ?? 37.6176,
    );
  }

  @override
  Future<void> updateDriver(Driver driver) async {
    await createDriver(driver);
  }

  @override
  Future<void> updateDriverLocation(String userId, DriverLocation location) {
    return updateDriverStatus(
      driverId: userId,
      isOnline: true,
      lat: location.lat,
      lng: location.lng,
    );
  }

  @override
  Future<void> setDriverOnlineStatus(String userId, bool isOnline) {
    return updateDriverStatus(
      driverId: userId,
      isOnline: isOnline,
      lat: 55.7558,
      lng: 37.6176,
    );
  }

  Future<void> updateDriverStatus({
    required String driverId,
    required bool isOnline,
    required double lat,
    required double lng,
  }) async {
    await _apiClient.post(
        '/api/v1/drivers/$driverId/status',
        <String, dynamic>{
          'status': isOnline ? 'online' : 'offline',
          'location': <String, dynamic>{'lat': lat, 'lng': lng},
        },
        headers: _authHeaders);
  }

  Future<Map<String, dynamic>> getDriverLocation(String driverId) async {
    final response = await _apiClient.get(
      '/api/v1/drivers/$driverId/location',
      headers: _authHeaders,
    );
    return response['location'] as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getAvailableOrders() {
    return _getOrdersByStatus('searching');
  }

  Future<Map<String, dynamic>> acceptOrder(String orderId) async {
    final response = await _apiClient.post(
      '/api/v1/orders/$orderId/accept',
      const <String, dynamic>{},
      headers: _authHeaders,
    );
    return response['order'] as Map<String, dynamic>;
  }

  Future<void> updateOrderStatus({
    required String orderId,
    required String status,
  }) async {
    await _apiClient.post(
        '/api/v1/orders/$orderId/status',
        <String, dynamic>{
          'status': status,
        },
        headers: _authHeaders);
  }

  Future<Map<String, dynamic>> getActiveOrder(String driverId) async {
    for (final status in const <String>['accepted', 'arrived', 'in_progress']) {
      final orders = await _getOrdersByStatus(status);
      for (final order in orders) {
        if (order['driver_id'] == driverId) {
          return order;
        }
      }
    }
    throw StateError('No active order found');
  }

  Future<List<Map<String, dynamic>>> getDriverOrders(String driverId) async {
    final results = <Map<String, dynamic>>[];
    for (final status in const <String>[
      'accepted',
      'arrived',
      'in_progress',
      'completed',
      'cancelled',
    ]) {
      final orders = await _getOrdersByStatus(status);
      results.addAll(orders.where((order) => order['driver_id'] == driverId));
    }
    return results;
  }

  @override
  Stream<Driver?> watchDriver(String userId) async* {
    while (true) {
      yield await getDriver(userId);
      await Future<void>.delayed(const Duration(seconds: 5));
    }
  }

  @override
  Stream<List<Driver>> watchOnlineDrivers() async* {
    yield const <Driver>[];
  }

  Future<List<Map<String, dynamic>>> _getOrdersByStatus(String status) async {
    final response = await _apiClient.get(
      '/api/v1/orders?status=$status',
      headers: _authHeaders,
    );
    final orders = response['orders'] as List<dynamic>? ?? const [];
    return orders.cast<Map<String, dynamic>>();
  }
}

AvailableOrder availableOrderFromBackend(Map<String, dynamic> map) {
  final order = Order.fromMap(map);
  return AvailableOrder(
    id: order.id,
    vehicleType: order.vehicleType,
    vehicleModel: 'Автомобиль клиента',
    pickupAddress: order.pickupLocation.address,
    dropoffAddress: order.dropoffLocation.address,
    pickupLat: order.pickupLocation.lat,
    pickupLng: order.pickupLocation.lng,
    dropoffLat: order.dropoffLocation.lat,
    dropoffLng: order.dropoffLocation.lng,
    distanceKm: order.distance == 0 ? 5.2 : order.distance,
    estimatedMinutes: 15,
    price: order.estimatedPrice == 0 ? 2500 : order.estimatedPrice,
    problemType: _problemTypeFromNotes(order.notes),
    blockedWheelsCount: _blockedWheelsFromNotes(order.notes),
    severity: ProblemSeverity.medium,
    createdAt: order.createdAt,
    clientName: 'Клиент EVIK',
    clientPhone: '+7 900 000-00-00',
  );
}

ActiveOrder activeOrderFromBackend(Map<String, dynamic> map) {
  final available = availableOrderFromBackend(map);
  final status = map['status']?.toString();
  return ActiveOrder(
    id: available.id,
    clientName: available.clientName,
    clientPhone: available.clientPhone,
    vehicleModel: available.vehicleModel,
    problemType: available.problemType,
    blockedWheelsCount: available.blockedWheelsCount,
    pickupAddress: available.pickupAddress,
    dropoffAddress: available.dropoffAddress,
    pickupLat: available.pickupLat,
    pickupLng: available.pickupLng,
    dropoffLat: available.dropoffLat,
    dropoffLng: available.dropoffLng,
    price: available.price,
    distanceToClient: available.distanceKm,
    totalDistance: available.distanceKm + 5.2,
    estimatedMinutes: available.estimatedMinutes,
    acceptedAt: DateTime.now(),
    status: switch (status) {
      'arrived' => ActiveOrderStatus.arrivedAtClient,
      'in_progress' => ActiveOrderStatus.drivingToDestination,
      'completed' => ActiveOrderStatus.completed,
      _ => ActiveOrderStatus.drivingToClient,
    },
  );
}

int _blockedWheelsFromNotes(String? notes) {
  final match = RegExp(r'Заблокировано колес:\s*(\d+)').firstMatch(notes ?? '');
  return int.tryParse(match?.group(1) ?? '') ?? 0;
}

String _problemTypeFromNotes(String? notes) {
  final text = notes?.trim();
  if (text == null || text.isEmpty) return 'Эвакуация';
  final lines = text
      .split('\n')
      .where((line) => !line.startsWith('Заблокировано колес:'))
      .where((line) => !line.startsWith('Комментарий клиента:'))
      .toList();
  return lines.isEmpty ? 'Эвакуация' : lines.first;
}
