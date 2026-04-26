import '../../features/order/domain/entities/order.dart';

class VehicleMultipliers {
  const VehicleMultipliers({
    required this.light,
    required this.suv,
    required this.minibus,
    required this.truck,
  });

  final double light;
  final double suv;
  final double minibus;
  final double truck;

  double getMultiplier(VehicleType vehicleType) {
    switch (vehicleType) {
      case VehicleType.light:
        return light;
      case VehicleType.suv:
        return suv;
      case VehicleType.minibus:
        return minibus;
      case VehicleType.truck:
        return truck;
    }
  }

  factory VehicleMultipliers.fromMap(Map<String, dynamic> map) {
    return VehicleMultipliers(
      light: (map['light'] as num).toDouble(),
      suv: (map['suv'] as num).toDouble(),
      minibus: (map['minibus'] as num).toDouble(),
      truck: (map['truck'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'light': light,
      'suv': suv,
      'minibus': minibus,
      'truck': truck,
    };
  }
}

class Tariff {
  const Tariff({
    required this.baseFare,
    required this.pricePerKm,
    required this.minimumFare,
    required this.vehicleMultipliers,
  });

  final double baseFare;
  final double pricePerKm;
  final double minimumFare;
  final VehicleMultipliers vehicleMultipliers;

  /// Рассчитывает стоимость поездки
  double calculatePrice(double distance, VehicleType vehicleType) {
    final basePrice = baseFare + (pricePerKm * distance);
    final multiplier = vehicleMultipliers.getMultiplier(vehicleType);
    final finalPrice = basePrice * multiplier;

    // Минимальная стоимость
    return finalPrice < minimumFare ? minimumFare : finalPrice;
  }

  factory Tariff.fromMap(Map<String, dynamic> map) {
    return Tariff(
      baseFare: (map['baseFare'] as num).toDouble(),
      pricePerKm: (map['pricePerKm'] as num).toDouble(),
      minimumFare: (map['minimumFare'] as num).toDouble(),
      vehicleMultipliers: VehicleMultipliers.fromMap(
        map['vehicleMultipliers'] as Map<String, dynamic>,
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'baseFare': baseFare,
      'pricePerKm': pricePerKm,
      'minimumFare': minimumFare,
      'vehicleMultipliers': vehicleMultipliers.toMap(),
    };
  }
}