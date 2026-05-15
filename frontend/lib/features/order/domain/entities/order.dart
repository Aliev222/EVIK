enum OrderStatus {
  searching,
  assigned,
  onWay,
  arrived,
  evacuating,
  completed,
  cancelled,
}

// State enum used in UI layer for order state management
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

enum VehicleType {
  light,
  suv,
  minibus,
  truck,
}

enum PaymentMethod {
  cash,
  card,
}

class LocationModel {
  const LocationModel({
    required this.lat,
    required this.lng,
    required this.address,
  });

  final double lat;
  final double lng;
  final String address;

  factory LocationModel.fromMap(Map<String, dynamic> map) {
    return LocationModel(
      lat: (map['lat'] as num).toDouble(),
      lng: (map['lng'] as num).toDouble(),
      address: map['address'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'lat': lat,
      'lng': lng,
      'address': address,
    };
  }
}

class Order {
  const Order({
    required this.id,
    required this.clientId,
    this.driverId,
    required this.status,
    required this.pickupLocation,
    required this.dropoffLocation,
    required this.vehicleType,
    required this.distance,
    required this.estimatedPrice,
    this.finalPrice,
    required this.paymentMethod,
    required this.createdAt,
    this.assignedAt,
    this.arrivedAt,
    this.completedAt,
    this.notes,
    this.paymentId,
    this.paymentStatus,
    this.paymentConfirmationUrl,
  });

  final String id;
  final String clientId;
  final String? driverId;
  final OrderStatus status;
  final LocationModel pickupLocation;
  final LocationModel dropoffLocation;
  final VehicleType vehicleType;
  final double distance; // in km
  final double estimatedPrice;
  final double? finalPrice;
  final PaymentMethod paymentMethod;
  final DateTime createdAt;
  final DateTime? assignedAt;
  final DateTime? arrivedAt;
  final DateTime? completedAt;
  final String? notes;
  final String? paymentId;
  final String? paymentStatus;
  final String? paymentConfirmationUrl;

  String get userId => clientId;
  OrderState get state => _statusToState(status);

  Order copyWith({
    String? id,
    String? clientId,
    String? driverId,
    OrderStatus? status,
    LocationModel? pickupLocation,
    LocationModel? dropoffLocation,
    VehicleType? vehicleType,
    double? distance,
    double? estimatedPrice,
    double? finalPrice,
    PaymentMethod? paymentMethod,
    DateTime? createdAt,
    DateTime? assignedAt,
    DateTime? arrivedAt,
    DateTime? completedAt,
    String? notes,
    String? paymentId,
    String? paymentStatus,
    String? paymentConfirmationUrl,
  }) {
    return Order(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      driverId: driverId ?? this.driverId,
      status: status ?? this.status,
      pickupLocation: pickupLocation ?? this.pickupLocation,
      dropoffLocation: dropoffLocation ?? this.dropoffLocation,
      vehicleType: vehicleType ?? this.vehicleType,
      distance: distance ?? this.distance,
      estimatedPrice: estimatedPrice ?? this.estimatedPrice,
      finalPrice: finalPrice ?? this.finalPrice,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      createdAt: createdAt ?? this.createdAt,
      assignedAt: assignedAt ?? this.assignedAt,
      arrivedAt: arrivedAt ?? this.arrivedAt,
      completedAt: completedAt ?? this.completedAt,
      notes: notes ?? this.notes,
      paymentId: paymentId ?? this.paymentId,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paymentConfirmationUrl:
          paymentConfirmationUrl ?? this.paymentConfirmationUrl,
    );
  }

  factory Order.fromMap(Map<String, dynamic> map) {
    if (map.containsKey('user_id') ||
        map.containsKey('pickup_lat') ||
        map.containsKey('dropoff_lat')) {
      final pickupLat = (map['pickup_lat'] as num?)?.toDouble() ??
          ((map['pickup'] as Map<String, dynamic>?)?['lat'] as num?)
              ?.toDouble() ??
          0.0;
      final pickupLng = (map['pickup_lng'] as num?)?.toDouble() ??
          ((map['pickup'] as Map<String, dynamic>?)?['lng'] as num?)
              ?.toDouble() ??
          0.0;
      final dropoffLat = (map['dropoff_lat'] as num?)?.toDouble() ??
          ((map['dropoff'] as Map<String, dynamic>?)?['lat'] as num?)
              ?.toDouble() ??
          0.0;
      final dropoffLng = (map['dropoff_lng'] as num?)?.toDouble() ??
          ((map['dropoff'] as Map<String, dynamic>?)?['lng'] as num?)
              ?.toDouble() ??
          0.0;

      return Order(
        id: map['id']?.toString() ?? '',
        clientId: map['user_id']?.toString() ?? '',
        driverId: map['driver_id']?.toString(),
        status: _parseStatus(map['status']?.toString()),
        pickupLocation: LocationModel(
          lat: pickupLat,
          lng: pickupLng,
          address: map['pickup_address']?.toString() ?? 'Точка подачи',
        ),
        dropoffLocation: LocationModel(
          lat: dropoffLat,
          lng: dropoffLng,
          address: map['dropoff_address']?.toString() ?? 'Точка доставки',
        ),
        vehicleType: _parseVehicleType(map['vehicle_type']?.toString()),
        distance: (map['distance'] as num?)?.toDouble() ?? 0.0,
        estimatedPrice: (map['estimated_price'] as num?)?.toDouble() ?? 0.0,
        finalPrice: (map['final_price'] as num?)?.toDouble(),
        paymentMethod: _parsePaymentMethod(map['payment_method']?.toString()),
        createdAt: _parseDateTime(map['created_at']),
        assignedAt: _parseDateTimeOrNull(map['assigned_at']),
        arrivedAt: _parseDateTimeOrNull(map['arrived_at']),
        completedAt: _parseDateTimeOrNull(map['completed_at']),
        notes: map['notes']?.toString(),
        paymentId: map['payment_id']?.toString(),
        paymentStatus: map['payment_status']?.toString(),
        paymentConfirmationUrl: map['confirmation_url']?.toString(),
      );
    }

    return Order(
      id: map['id'] as String,
      clientId: map['clientId'] as String,
      driverId: map['driverId'] as String?,
      status: OrderStatus.values.byName(map['status'] as String),
      pickupLocation:
          LocationModel.fromMap(map['pickupLocation'] as Map<String, dynamic>),
      dropoffLocation:
          LocationModel.fromMap(map['dropoffLocation'] as Map<String, dynamic>),
      vehicleType: VehicleType.values.byName(map['vehicleType'] as String),
      distance: (map['distance'] as num).toDouble(),
      estimatedPrice: (map['estimatedPrice'] as num).toDouble(),
      finalPrice: map['finalPrice'] != null
          ? (map['finalPrice'] as num).toDouble()
          : null,
      paymentMethod:
          PaymentMethod.values.byName(map['paymentMethod'] as String),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
      assignedAt: map['assignedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['assignedAt'] as int)
          : null,
      arrivedAt: map['arrivedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['arrivedAt'] as int)
          : null,
      completedAt: map['completedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['completedAt'] as int)
          : null,
      notes: map['notes'] as String?,
      paymentId: map['paymentId'] as String?,
      paymentStatus: map['paymentStatus'] as String?,
      paymentConfirmationUrl: map['paymentConfirmationUrl'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'clientId': clientId,
      'driverId': driverId,
      'status': status.name,
      'pickupLocation': pickupLocation.toMap(),
      'dropoffLocation': dropoffLocation.toMap(),
      'vehicleType': vehicleType.name,
      'distance': distance,
      'estimatedPrice': estimatedPrice,
      'finalPrice': finalPrice,
      'paymentMethod': paymentMethod.name,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'assignedAt': assignedAt?.millisecondsSinceEpoch,
      'arrivedAt': arrivedAt?.millisecondsSinceEpoch,
      'completedAt': completedAt?.millisecondsSinceEpoch,
      'notes': notes,
      'paymentId': paymentId,
      'paymentStatus': paymentStatus,
      'paymentConfirmationUrl': paymentConfirmationUrl,
    };
  }

  static OrderStatus _parseStatus(String? status) {
    return switch (status) {
      'searching' => OrderStatus.searching,
      'accepted' => OrderStatus.assigned,
      'assigned' => OrderStatus.assigned,
      'on_way' => OrderStatus.onWay,
      'arrived' => OrderStatus.arrived,
      'in_progress' => OrderStatus.evacuating,
      'evacuating' => OrderStatus.evacuating,
      'completed' => OrderStatus.completed,
      'cancelled' => OrderStatus.cancelled,
      _ => OrderStatus.searching,
    };
  }

  static VehicleType _parseVehicleType(String? value) {
    return switch (value) {
      'suv' => VehicleType.suv,
      'minibus' => VehicleType.minibus,
      'truck' => VehicleType.truck,
      _ => VehicleType.light,
    };
  }

  static PaymentMethod _parsePaymentMethod(String? value) {
    return switch (value) {
      'card' => PaymentMethod.card,
      _ => PaymentMethod.cash,
    };
  }

  static DateTime _parseDateTime(Object? value) {
    return _parseDateTimeOrNull(value) ?? DateTime.now();
  }

  static DateTime? _parseDateTimeOrNull(Object? value) {
    if (value == null) return null;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  static OrderState _statusToState(OrderStatus status) {
    return switch (status) {
      OrderStatus.searching => OrderState.searching,
      OrderStatus.assigned => OrderState.accepted,
      OrderStatus.onWay => OrderState.accepted,
      OrderStatus.arrived => OrderState.arrived,
      OrderStatus.evacuating => OrderState.inProgress,
      OrderStatus.completed => OrderState.completed,
      OrderStatus.cancelled => OrderState.cancelled,
    };
  }
}
