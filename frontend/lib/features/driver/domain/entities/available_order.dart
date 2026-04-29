import '../../../order/domain/entities/order.dart';

class AvailableOrder {
  final String id;
  final VehicleType vehicleType;
  final String vehicleModel;
  final String pickupAddress;
  final String dropoffAddress;
  final double pickupLat;
  final double pickupLng;
  final double dropoffLat;
  final double dropoffLng;
  final double distanceKm;
  final int estimatedMinutes;
  final double price;
  final String problemType;
  final int blockedWheelsCount;
  final ProblemSeverity severity;
  final DateTime createdAt;
  final String clientName;
  final String clientPhone;

  const AvailableOrder({
    required this.id,
    required this.vehicleType,
    required this.vehicleModel,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.pickupLat,
    required this.pickupLng,
    required this.dropoffLat,
    required this.dropoffLng,
    required this.distanceKm,
    required this.estimatedMinutes,
    required this.price,
    required this.problemType,
    required this.blockedWheelsCount,
    required this.severity,
    required this.createdAt,
    required this.clientName,
    required this.clientPhone,
  });

  String get vehicleIcon {
    switch (vehicleType) {
      case VehicleType.light:
        return '🚗';
      case VehicleType.suv:
        return '🚙';
      case VehicleType.truck:
        return '🚚';
      default:
        return '🚗';
    }
  }

  String get vehicleDisplayName {
    switch (vehicleType) {
      case VehicleType.light:
        return 'Легковой';
      case VehicleType.suv:
        return 'Внедорожник';
      case VehicleType.truck:
        return 'Грузовой';
      default:
        return 'Автомобиль';
    }
  }
}

enum ProblemSeverity {
  low, // Не заводится
  medium, // Прокол колеса
  high, // ДТП
}

extension ProblemSeverityExtension on ProblemSeverity {
  String get displayName {
    switch (this) {
      case ProblemSeverity.low:
        return 'Не заводится';
      case ProblemSeverity.medium:
        return 'Поломка';
      case ProblemSeverity.high:
        return 'ДТП';
    }
  }

  String get colorName {
    switch (this) {
      case ProblemSeverity.low:
        return 'orange';
      case ProblemSeverity.medium:
        return 'blue';
      case ProblemSeverity.high:
        return 'red';
    }
  }
}
