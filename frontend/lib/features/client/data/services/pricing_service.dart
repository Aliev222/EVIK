import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client_stub.dart'
    if (dart.library.io) '../../../../core/network/api_client_io.dart'
    as platform_api;
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../map/domain/entities/map_location.dart';
import '../../../order/domain/entities/order.dart';
import '../../../order/domain/entities/order_flow_state.dart';

class PricingService {
  const PricingService({required String? accessToken})
      : _accessToken = accessToken;

  final String? _accessToken;

  Map<String, String>? get _authHeaders {
    final token = _accessToken;
    if (token == null || token.isEmpty) return null;
    return <String, String>{'Authorization': 'Bearer $token'};
  }

  Future<double> calculatePrice({
    required MapLocation pickup,
    required MapLocation dropoff,
    required VehicleType vehicleType,
    required DateTime timeOfDay,
    TowTruckType towTruckType = TowTruckType.winch,
  }) async {
    final json = await platform_api.createPlatformApiClient().post(
          '/api/v1/pricing/calculate',
          <String, dynamic>{
            'pickup_lat': pickup.latitude,
            'pickup_lng': pickup.longitude,
            'dropoff_lat': dropoff.latitude,
            'dropoff_lng': dropoff.longitude,
            'tow_truck_type': towTruckType.name,
          },
          headers: _authHeaders,
        );
    return (json['total_price'] as num).toDouble() / 100;
  }

  Future<PriceRange> calculatePriceRange({
    required MapLocation pickup,
    required MapLocation dropoff,
    required VehicleType vehicleType,
    required DateTime timeOfDay,
    TowTruckType towTruckType = TowTruckType.winch,
  }) async {
    final price = await calculatePrice(
      pickup: pickup,
      dropoff: dropoff,
      vehicleType: vehicleType,
      timeOfDay: timeOfDay,
      towTruckType: towTruckType,
    );
    return PriceRange(minPrice: price, maxPrice: price, basePrice: price);
  }

  String formatPriceRange(PriceRange range) => formatPrice(range.basePrice);

  String formatPrice(double price) => '${price.round()} ₽';
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
  final token = ref.watch(authProvider.select((state) => state.accessToken));
  return PricingService(accessToken: token);
});
