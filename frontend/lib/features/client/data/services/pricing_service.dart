import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/price_calculator.dart';
import '../../../../shared/providers/tariff_provider.dart';
import '../../../map/domain/entities/map_location.dart';
import '../../../order/domain/entities/order.dart';

class PricingService {
  PricingService({
    required this.priceCalculator,
    required this.ref,
  });

  final PriceCalculator priceCalculator;
  final Ref ref;

  Future<double> calculatePrice({
    required MapLocation pickup,
    required MapLocation dropoff,
    required VehicleType vehicleType,
    required DateTime timeOfDay,
  }) async {
    try {
      final tariff = await ref.read(currentTariffProvider.future);
      final result = await priceCalculator.calculatePrice(
        pickupLocation: pickup.toLocationModel(),
        dropoffLocation: dropoff.toLocationModel(),
        vehicleType: vehicleType,
        tariff: tariff,
      );

      var finalPrice = result.estimatedPrice;
      if (_isNightTime(timeOfDay)) {
        finalPrice *= 1.3;
      }
      if (_isHoliday(timeOfDay)) {
        finalPrice *= 1.15;
      }
      return finalPrice;
    } catch (_) {
      return _fallbackPriceCalculation(pickup, dropoff, vehicleType);
    }
  }

  Future<PriceRange> calculatePriceRange({
    required MapLocation pickup,
    required MapLocation dropoff,
    required VehicleType vehicleType,
    required DateTime timeOfDay,
  }) async {
    final basePrice = await calculatePrice(
      pickup: pickup,
      dropoff: dropoff,
      vehicleType: vehicleType,
      timeOfDay: timeOfDay,
    );

    return PriceRange(
      minPrice: basePrice * 0.85,
      maxPrice: basePrice * 1.15,
      basePrice: basePrice,
    );
  }

  double _fallbackPriceCalculation(
    MapLocation pickup,
    MapLocation dropoff,
    VehicleType vehicleType,
  ) {
    final basePrice = switch (vehicleType) {
      VehicleType.light => 2500.0,
      VehicleType.suv => 3100.0,
      VehicleType.minibus => 3800.0,
      VehicleType.truck => 4500.0,
    };

    final distance = _calculateStraightDistance(pickup, dropoff);
    final distancePrice = distance > 5 ? (distance - 5) * 150 : 0;
    return basePrice + distancePrice;
  }

  double _calculateStraightDistance(MapLocation from, MapLocation to) {
    const earthRadius = 6371.0;
    final lat1 = _toRadians(from.latitude);
    final lat2 = _toRadians(to.latitude);
    final dLat = _toRadians(to.latitude - from.latitude);
    final dLng = _toRadians(to.longitude - from.longitude);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c * 1.2;
  }

  bool _isNightTime(DateTime dateTime) =>
      dateTime.hour >= 22 || dateTime.hour <= 7;

  bool _isHoliday(DateTime dateTime) =>
      dateTime.weekday == DateTime.saturday ||
      dateTime.weekday == DateTime.sunday;

  String formatPrice(double price) => priceCalculator.formatPrice(price);

  String formatPriceRange(PriceRange range) =>
      '${formatPrice(range.minPrice)} - ${formatPrice(range.maxPrice)}';

  double _toRadians(double degrees) => degrees * math.pi / 180;
}

class PriceRange {
  const PriceRange({
    required this.minPrice,
    required this.maxPrice,
    required this.basePrice,
  });

  final double minPrice;
  final double maxPrice;
  final double basePrice;
}

final pricingServiceProvider = Provider<PricingService>((ref) {
  return PricingService(
    priceCalculator: PriceCalculator(),
    ref: ref,
  );
});
