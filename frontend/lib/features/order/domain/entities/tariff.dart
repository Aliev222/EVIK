import 'package:tow_truck_frontend/features/order/domain/entities/order_flow_state.dart';

class Tariff {
  const Tariff({
    required this.towTruckType,
    required this.basePrice,
    required this.pricePerKm,
    required this.minimumPrice,
  });

  final TowTruckType towTruckType;
  final int basePrice;
  final int pricePerKm;
  final int minimumPrice;

  double estimateRub(double distanceKm) {
    final raw = basePrice + (pricePerKm * distanceKm).round();
    final total = raw < minimumPrice ? minimumPrice : raw;
    return total / 100.0;
  }

  static TowTruckType? _parseType(String? value) {
    switch (value) {
      case 'winch':
        return TowTruckType.winch;
      case 'platform':
        return TowTruckType.platform;
      case 'manipulator':
        return TowTruckType.manipulator;
      default:
        return null;
    }
  }

  static Tariff? fromJson(Map<String, dynamic> json) {
    final type = _parseType(json['tow_truck_type'] as String?);
    if (type == null) return null;
    return Tariff(
      towTruckType: type,
      basePrice: (json['base_price'] as num?)?.toInt() ?? 0,
      pricePerKm: (json['price_per_km'] as num?)?.toInt() ?? 0,
      minimumPrice: (json['minimum_price'] as num?)?.toInt() ?? 0,
    );
  }
}
