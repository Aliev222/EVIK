import 'dart:math' as math;

import '../../features/order/domain/entities/order.dart';
import '../../shared/models/tariff_model.dart';
import 'location_service.dart';

class PriceCalculator {
  static PriceCalculator? _instance;

  PriceCalculator._(this._locationService);

  final LocationService _locationService;

  factory PriceCalculator({LocationService? locationService}) {
    _instance ??= PriceCalculator._(locationService ?? LocationService());
    return _instance!;
  }

  Future<PriceCalculationResult> calculatePrice({
    required LocationModel pickupLocation,
    required LocationModel dropoffLocation,
    required VehicleType vehicleType,
    required Tariff tariff,
  }) async {
    try {
      final routeDistance = await _locationService.calculateRouteDistance(
        from: pickupLocation,
        to: dropoffLocation,
      );
      final distance = routeDistance ??
          _calculateStraightDistance(pickupLocation, dropoffLocation);
      final estimatedPrice = tariff.calculatePrice(distance, vehicleType);

      return PriceCalculationResult(
        distance: distance,
        estimatedPrice: estimatedPrice,
        isApproximate: routeDistance == null,
      );
    } catch (e) {
      throw PriceCalculationException('Ошибка расчета стоимости: $e');
    }
  }

  double _calculateStraightDistance(LocationModel from, LocationModel to) {
    const earthRadiusKm = 6371.0;
    final lat1 = _toRadians(from.lat);
    final lat2 = _toRadians(to.lat);
    final deltaLat = _toRadians(to.lat - from.lat);
    final deltaLng = _toRadians(to.lng - from.lng);

    final a = math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(deltaLng / 2) *
            math.sin(deltaLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c * 1.2;
  }

  String formatPrice(double price) {
    if (price < 1000) {
      return '${price.toInt()} ₽';
    }

    final thousands = price ~/ 1000;
    final remainder = ((price % 1000) / 100).round();
    return remainder == 0
        ? '$thousands тыс. ₽'
        : '$thousands.$remainder тыс. ₽';
  }

  int calculateEstimatedArrivalTime({
    required LocationModel driverLocation,
    required LocationModel pickupLocation,
  }) {
    final distance = _calculateStraightDistance(driverLocation, pickupLocation);
    final timeInMinutes = ((distance / 30) * 60).round();
    return timeInMinutes.clamp(10, 60);
  }

  double _toRadians(double degrees) => degrees * math.pi / 180;
}

class PriceCalculationResult {
  const PriceCalculationResult({
    required this.distance,
    required this.estimatedPrice,
    required this.isApproximate,
  });

  final double distance;
  final double estimatedPrice;
  final bool isApproximate;

  String get distanceText => distance < 1
      ? '${(distance * 1000).round()} м'
      : '${distance.toStringAsFixed(1)} км';
}

class PriceCalculationException implements Exception {
  const PriceCalculationException(this.message);

  final String message;

  @override
  String toString() => 'PriceCalculationException: $message';
}
