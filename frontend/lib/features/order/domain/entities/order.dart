enum OrderState {
  idle,
  searching,
  accepted,
  arrived,
  inProgress,
  completed,
  cancelled,
  noDriverFound,
}

class Coordinate {
  const Coordinate({required this.lat, required this.lng});

  final double lat;
  final double lng;
}

class Order {
  const Order({
    required this.id,
    required this.userId,
    required this.pickup,
    required this.dropoff,
    required this.state,
    this.driverId,
  });

  final String id;
  final String userId;
  final Coordinate pickup;
  final Coordinate dropoff;
  final OrderState state;
  final String? driverId;

  Order copyWith({
    String? id,
    String? userId,
    Coordinate? pickup,
    Coordinate? dropoff,
    OrderState? state,
    String? driverId,
  }) {
    return Order(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      pickup: pickup ?? this.pickup,
      dropoff: dropoff ?? this.dropoff,
      state: state ?? this.state,
      driverId: driverId ?? this.driverId,
    );
  }
}
