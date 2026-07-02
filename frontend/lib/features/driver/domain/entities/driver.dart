import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';

class DriverEarnings {
  const DriverEarnings({
    required this.today,
    required this.week,
    required this.month,
  });

  final double today;
  final double week;
  final double month;

  factory DriverEarnings.fromMap(Map<String, dynamic> map) {
    return DriverEarnings(
      today: (map['today'] as num).toDouble(),
      week: (map['week'] as num).toDouble(),
      month: (map['month'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'today': today,
      'week': week,
      'month': month,
    };
  }
}

class DriverLocation {
  const DriverLocation({
    required this.lat,
    required this.lng,
    this.isMocked = false,
  });

  final double lat;
  final double lng;
  final bool isMocked;

  factory DriverLocation.fromMap(Map<String, dynamic> map) {
    return DriverLocation(
      lat: (map['lat'] as num).toDouble(),
      lng: (map['lng'] as num).toDouble(),
      isMocked: map['is_mock'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'lat': lat,
      'lng': lng,
      'is_mock': isMocked,
    };
  }
}

class Driver {
  const Driver({
    required this.userId,
    this.fullName,
    this.phone,
    required this.vehicleModel,
    required this.vehicleNumber,
    required this.vehicleType,
    required this.rating,
    required this.totalOrders,
    required this.isOnline,
    this.currentLocation,
    required this.isVerified,
    required this.earnings,
  });

  final String userId; // ссылка на users collection
  final String? fullName; // Real driver full name from backend
  final String? phone; // Real driver phone number from backend
  final String vehicleModel;
  final String vehicleNumber;
  final VehicleType vehicleType;
  final double rating; // 0-5
  final int totalOrders;
  final bool isOnline;
  final DriverLocation? currentLocation;
  final bool isVerified;
  final DriverEarnings earnings;

  Driver copyWith({
    String? userId,
    String? fullName,
    String? phone,
    String? vehicleModel,
    String? vehicleNumber,
    VehicleType? vehicleType,
    double? rating,
    int? totalOrders,
    bool? isOnline,
    DriverLocation? currentLocation,
    bool? isVerified,
    DriverEarnings? earnings,
  }) {
    return Driver(
      userId: userId ?? this.userId,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      vehicleModel: vehicleModel ?? this.vehicleModel,
      vehicleNumber: vehicleNumber ?? this.vehicleNumber,
      vehicleType: vehicleType ?? this.vehicleType,
      rating: rating ?? this.rating,
      totalOrders: totalOrders ?? this.totalOrders,
      isOnline: isOnline ?? this.isOnline,
      currentLocation: currentLocation ?? this.currentLocation,
      isVerified: isVerified ?? this.isVerified,
      earnings: earnings ?? this.earnings,
    );
  }

  factory Driver.fromMap(Map<String, dynamic> map) {
    // Handle new backend profile API response format
    if (map.containsKey('user_id') || map.containsKey('current_order_id')) {
      final status = map['status']?.toString();

      // Map vehicle_type from backend to VehicleType enum
      VehicleType vehicleType = VehicleType.light; // default
      final vehicleTypeStr = map['vehicle_type']?.toString();
      if (vehicleTypeStr != null) {
        switch (vehicleTypeStr) {
          case 'winch':
            vehicleType = VehicleType.light;
            break;
          case 'platform':
            vehicleType = VehicleType.truck;
            break;
          case 'manipulator':
            vehicleType = VehicleType.suv;
            break;
        }
      }

      return Driver(
        userId: map['user_id']?.toString() ?? map['id']?.toString() ?? '',
        fullName: map['full_name']?.toString(),
        phone: map['phone']?.toString(),
        vehicleModel: map['vehicle_model']?.toString().isNotEmpty == true
            ? map['vehicle_model']!.toString()
            : '',
        vehicleNumber: map['vehicle_plate']?.toString() ?? map['vehicle_number']?.toString() ?? '',
        vehicleType: vehicleType,
        rating: (map['rating_average'] as num?)?.toDouble() ??
                (map['rating'] as num?)?.toDouble() ??
                0.0,
        totalOrders: (map['total_orders'] as int?) ?? 0,
        isOnline: status == 'online' || status == 'busy',
        currentLocation: map['current_location'] != null
            ? DriverLocation.fromMap(
                map['current_location'] as Map<String, dynamic>)
            : null,
        isVerified: map['is_verified'] as bool? ?? true,
        earnings: DriverEarnings.fromMap(
          (map['earnings'] as Map<String, dynamic>?) ??
              const <String, dynamic>{'today': 0, 'week': 0, 'month': 0},
        ),
      );
    }

    // Handle legacy format
    return Driver(
      userId: map['userId'] as String,
      fullName: map['fullName'] as String?,
      phone: map['phone'] as String?,
      vehicleModel: map['vehicleModel'] as String,
      vehicleNumber: map['vehicleNumber'] as String,
      vehicleType: VehicleType.values.byName(map['vehicleType'] as String),
      rating: (map['rating'] as num).toDouble(),
      totalOrders: map['totalOrders'] as int,
      isOnline: map['isOnline'] as bool,
      currentLocation: map['currentLocation'] != null
          ? DriverLocation.fromMap(
              map['currentLocation'] as Map<String, dynamic>)
          : null,
      isVerified: map['isVerified'] as bool,
      earnings: DriverEarnings.fromMap(map['earnings'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'fullName': fullName,
      'phone': phone,
      'vehicleModel': vehicleModel,
      'vehicleNumber': vehicleNumber,
      'vehicleType': vehicleType.name,
      'rating': rating,
      'totalOrders': totalOrders,
      'isOnline': isOnline,
      'currentLocation': currentLocation?.toMap(),
      'isVerified': isVerified,
      'earnings': earnings.toMap(),
    };
  }
}
