class ActiveOrder {
  final String id;
  final String clientName;
  final String clientPhone;
  final String vehicleModel;
  final String problemType;
  final int blockedWheelsCount;
  final String pickupAddress;
  final String dropoffAddress;
  final double pickupLat;
  final double pickupLng;
  final double dropoffLat;
  final double dropoffLng;
  final double price;
  final double distanceToClient;
  final double totalDistance;
  final int estimatedMinutes;
  final DateTime acceptedAt;
  final ActiveOrderStatus status;

  const ActiveOrder({
    required this.id,
    required this.clientName,
    required this.clientPhone,
    required this.vehicleModel,
    required this.problemType,
    required this.blockedWheelsCount,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.pickupLat,
    required this.pickupLng,
    required this.dropoffLat,
    required this.dropoffLng,
    required this.price,
    required this.distanceToClient,
    required this.totalDistance,
    required this.estimatedMinutes,
    required this.acceptedAt,
    required this.status,
  });

  String get clientInitial {
    return clientName.isNotEmpty ? clientName[0].toUpperCase() : 'К';
  }

  String get statusDisplayName {
    switch (status) {
      case ActiveOrderStatus.drivingToClient:
        return 'Еду к клиенту';
      case ActiveOrderStatus.arrivedAtClient:
        return 'На месте';
      case ActiveOrderStatus.drivingToDestination:
        return 'Везу клиента';
      case ActiveOrderStatus.completed:
        return 'Завершен';
    }
  }

  ActiveOrder copyWith({
    String? id,
    String? clientName,
    String? clientPhone,
    String? vehicleModel,
    String? problemType,
    int? blockedWheelsCount,
    String? pickupAddress,
    String? dropoffAddress,
    double? pickupLat,
    double? pickupLng,
    double? dropoffLat,
    double? dropoffLng,
    double? price,
    double? distanceToClient,
    double? totalDistance,
    int? estimatedMinutes,
    DateTime? acceptedAt,
    ActiveOrderStatus? status,
  }) {
    return ActiveOrder(
      id: id ?? this.id,
      clientName: clientName ?? this.clientName,
      clientPhone: clientPhone ?? this.clientPhone,
      vehicleModel: vehicleModel ?? this.vehicleModel,
      problemType: problemType ?? this.problemType,
      blockedWheelsCount: blockedWheelsCount ?? this.blockedWheelsCount,
      pickupAddress: pickupAddress ?? this.pickupAddress,
      dropoffAddress: dropoffAddress ?? this.dropoffAddress,
      pickupLat: pickupLat ?? this.pickupLat,
      pickupLng: pickupLng ?? this.pickupLng,
      dropoffLat: dropoffLat ?? this.dropoffLat,
      dropoffLng: dropoffLng ?? this.dropoffLng,
      price: price ?? this.price,
      distanceToClient: distanceToClient ?? this.distanceToClient,
      totalDistance: totalDistance ?? this.totalDistance,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      status: status ?? this.status,
    );
  }
}

enum ActiveOrderStatus {
  drivingToClient,
  arrivedAtClient,
  drivingToDestination,
  completed,
}
