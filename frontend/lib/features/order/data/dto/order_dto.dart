import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';

class OrderDto {
  const OrderDto({
    required this.id,
    required this.userId,
    required this.pickupLat,
    required this.pickupLng,
    required this.dropoffLat,
    required this.dropoffLng,
    required this.status,
    this.driverId,
  });

  final String id;
  final String userId;
  final double pickupLat;
  final double pickupLng;
  final double dropoffLat;
  final double dropoffLng;
  final String status;
  final String? driverId;

  factory OrderDto.fromJson(Map<String, dynamic> json) {
    return OrderDto(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      pickupLat: (json['pickup_lat'] as num).toDouble(),
      pickupLng: (json['pickup_lng'] as num).toDouble(),
      dropoffLat: (json['dropoff_lat'] as num).toDouble(),
      dropoffLng: (json['dropoff_lng'] as num).toDouble(),
      status: json['status'] as String,
      driverId: json['driver_id'] as String?,
    );
  }

  Order toDomain() {
    return Order(
      id: id,
      userId: userId,
      pickup: Coordinate(lat: pickupLat, lng: pickupLng),
      dropoff: Coordinate(lat: dropoffLat, lng: dropoffLng),
      state: _mapStatus(status),
      driverId: driverId,
    );
  }

  static OrderState _mapStatus(String value) {
    return switch (value) {
      'searching' => OrderState.searching,
      'accepted' => OrderState.accepted,
      'arrived' => OrderState.arrived,
      'in_progress' => OrderState.inProgress,
      'completed' => OrderState.completed,
      'cancelled' => OrderState.cancelled,
      'no_driver_found' => OrderState.noDriverFound,
      _ => OrderState.idle,
    };
  }
}
