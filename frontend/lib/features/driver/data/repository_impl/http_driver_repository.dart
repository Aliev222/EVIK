import 'dart:async';

import 'package:tow_truck_frontend/core/network/api_client.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/active_order.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/available_order.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver.dart';
import 'package:tow_truck_frontend/features/driver/data/repository/driver_repository.dart';

class HttpDriverRepository implements DriverRepository {
  const HttpDriverRepository({
    required ApiClient apiClient,
    required String? accessToken,
    String? Function()? accessTokenProvider,
  })  : _apiClient = apiClient,
        _accessToken = accessToken,
        _accessTokenProvider = accessTokenProvider;

  final ApiClient _apiClient;
  final String? _accessToken;
  final String? Function()? _accessTokenProvider;

  Map<String, String>? get _authHeaders {
    final token = _accessTokenProvider?.call() ?? _accessToken;
    if (token == null || token.isEmpty) return null;
    return <String, String>{'Authorization': 'Bearer $token'};
  }

  Future<Driver> getDriverProfile(String driverId) async {
    final response = await _apiClient.get(
      '/api/v1/drivers/$driverId/profile',
      headers: _authHeaders,
    );
    return Driver.fromMap(response['profile'] as Map<String, dynamic>);
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
      lat: driver.currentLocation?.lat,
      lng: driver.currentLocation?.lng,
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
      isMock: location.isMocked,
    );
  }

  @override
  Future<void> setDriverOnlineStatus(String userId, bool isOnline) {
    return updateDriverStatus(
      driverId: userId,
      isOnline: isOnline,
      lat: null,
      lng: null,
    );
  }

  Future<void> updateDriverStatus({
    required String driverId,
    required bool isOnline,
    required double? lat,
    required double? lng,
    bool isMock = false,
  }) async {
    final body = <String, dynamic>{
      'status': isOnline ? 'online' : 'offline',
    };
    if (lat != null && lng != null) {
      body['location'] = <String, dynamic>{'lat': lat, 'lng': lng, 'is_mock': isMock};
    }
    await _apiClient.post(
        '/api/v1/drivers/$driverId/status',
        body,
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

  Future<Map<String, dynamic>?> getCurrentOffer() async {
    try {
      final response = await _apiClient.get(
        '/api/v1/driver/current-offer',
        headers: _authHeaders,
      );
      final offer = response['offer'];
      if (offer == null) return null;
      return offer as Map<String, dynamic>;
    } on ApiClientException {
      return null;
    }
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
    for (final status in const <String>['accepted', 'arrived', 'in_progress', 'awaiting_payment']) {
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

  Future<void> declineOffer(String orderId) async {
    try {
      await _apiClient.post(
        '/api/v1/orders/$orderId/decline',
        const <String, dynamic>{},
        headers: _authHeaders,
      );
    } on ApiClientException {
      // Server will expire the offer on its own — network errors are fine.
    }
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

  // Use real vehicle type text instead of generic text
  String vehicleModel = '';
  switch (order.vehicleType) {
    case VehicleType.light:
      vehicleModel = 'Легковой автомобиль';
      break;
    case VehicleType.suv:
      vehicleModel = 'Внедорожник';
      break;
    case VehicleType.minibus:
      vehicleModel = 'Минивэн';
      break;
    case VehicleType.truck:
      vehicleModel = 'Грузовой автомобиль';
      break;
  }

  return AvailableOrder(
    id: order.id,
    vehicleType: order.vehicleType,
    vehicleModel: vehicleModel,
    pickupAddress: order.pickupLocation.address,
    dropoffAddress: order.dropoffLocation.address,
    pickupLat: order.pickupLocation.lat,
    pickupLng: order.pickupLocation.lng,
    dropoffLat: order.dropoffLocation.lat,
    dropoffLng: order.dropoffLocation.lng,
    distanceKm: order.distance > 0 ? order.distance : 0, // Use 0 if no distance instead of fake 5.2
    estimatedMinutes: _estimateMinutes(order.distance),
    price: order.estimatedPrice > 0 ? order.estimatedPrice : 0, // Use 0 if no price instead of fake 2500
    problemType: _problemTypeFromNotes(order.notes),
    blockedWheelsCount: _blockedWheelsFromNotes(order.notes),
    severity: _severityFromNotes(order.notes), // Calculate severity from notes instead of hardcoded medium
    createdAt: order.createdAt,
    // The backend attaches client_name/client_phone only for orders the driver
    // is assigned to (see enrichWithClient). The searching pool never carries
    // client identity, so we fall back to a neutral label.
    clientName: _clientDisplayName(map['client_name']?.toString()),
    clientPhone: map['client_phone']?.toString() ?? '',
  );
}

/// Renders the backend client label; for clients that is the phone or the
/// neutral marker for a deleted account. Falls back to 'Клиент'.
String _clientDisplayName(String? raw) {
  final value = raw?.trim() ?? '';
  return value.isEmpty ? 'Клиент' : value;
}

AvailableOrder availableOrderFromOffer(Map<String, dynamic> map, String orderId) {
  final vehicleType = switch (map['tow_truck_type']?.toString()) {
    'light' => VehicleType.light,
    'suv' => VehicleType.suv,
    'minibus' => VehicleType.minibus,
    'truck' => VehicleType.truck,
    _ => VehicleType.light,
  };
  final vehicleModel = switch (vehicleType) {
    VehicleType.light => 'Легковой автомобиль',
    VehicleType.suv => 'Внедорожник',
    VehicleType.minibus => 'Минивэн',
    VehicleType.truck => 'Грузовой автомобиль',
  };
  final priceTotal = (map['price_total'] as num?)?.toDouble() ?? 0;
  final distanceKm = (map['distance_km'] as num?)?.toDouble() ?? 0;

  DateTime? expiresAt;
  final expiresAtStr = map['expires_at']?.toString();
  if (expiresAtStr != null && expiresAtStr.isNotEmpty) {
    expiresAt = DateTime.tryParse(expiresAtStr)?.toUtc();
  }

  return AvailableOrder(
    id: orderId,
    offerId: map['offer_id']?.toString() ?? '',
    vehicleType: vehicleType,
    vehicleModel: vehicleModel,
    pickupAddress: map['pickup_address']?.toString() ?? '',
    dropoffAddress: map['dropoff_address']?.toString() ?? '',
    pickupLat: (map['pickup_lat'] as num?)?.toDouble() ?? 0,
    pickupLng: (map['pickup_lng'] as num?)?.toDouble() ?? 0,
    dropoffLat: (map['dropoff_lat'] as num?)?.toDouble() ?? 0,
    dropoffLng: (map['dropoff_lng'] as num?)?.toDouble() ?? 0,
    distanceKm: distanceKm,
    estimatedMinutes: _estimateMinutes(distanceKm),
    price: priceTotal > 0 ? priceTotal / 100 : 0,
    problemType: 'Эвакуация',
    blockedWheelsCount: 0,
    severity: ProblemSeverity.medium,
    createdAt: DateTime.now(),
    expiresAt: expiresAt,
    clientName: 'Клиент',
    clientPhone: '',
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
    paymentMethod: map['payment_method']?.toString() == 'card'
        ? PaymentMethod.card
        : PaymentMethod.cash,
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

/// Estimate minutes based on distance (real calculation instead of hardcoded)
int _estimateMinutes(double distance) {
  if (distance <= 0) return 0; // No estimate available

  // Simple calculation: assume 40 km/h average speed in city
  final hours = distance / 40;
  final minutes = (hours * 60).round();

  // Minimum 5 minutes, maximum 120 minutes
  return minutes.clamp(5, 120);
}

/// Calculate severity from order notes (real logic instead of hardcoded medium)
ProblemSeverity _severityFromNotes(String? notes) {
  if (notes == null || notes.isEmpty) return ProblemSeverity.medium;

  final lowerNotes = notes.toLowerCase();

  // High priority keywords
  if (lowerNotes.contains('срочно') ||
      lowerNotes.contains('авария') ||
      lowerNotes.contains('дтп') ||
      lowerNotes.contains('поломка')) {
    return ProblemSeverity.high;
  }

  // Low priority keywords
  if (lowerNotes.contains('не спешу') ||
      lowerNotes.contains('когда удобно') ||
      lowerNotes.contains('планово')) {
    return ProblemSeverity.low;
  }

  // Default to medium
  return ProblemSeverity.medium;
}
