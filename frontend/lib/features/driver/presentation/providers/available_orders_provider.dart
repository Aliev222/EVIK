import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/features/order/presentation/providers/order_provider.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/driver_status_provider.dart';
import 'driver_provider.dart';

enum AvailableOrdersDistanceFilter {
  under5km,
  under10km,
  all,
}

enum AvailableOrdersSort {
  price,
  distance,
  createdAt,
}

final availableOrdersDistanceFilterProvider =
    StateProvider<AvailableOrdersDistanceFilter>((ref) {
  return AvailableOrdersDistanceFilter.under10km;
});

final availableOrdersSortProvider = StateProvider<AvailableOrdersSort>((ref) {
  return AvailableOrdersSort.distance;
});

final availableOrdersProvider = StreamProvider.autoDispose<List<Order>>((ref) {
  final user = ref.watch(currentUserProvider);
  final driver =
      user == null ? null : ref.watch(watchDriverProvider(user.id)).valueOrNull;
  final status = ref.watch(driverStatusProvider);
  final filter = ref.watch(availableOrdersDistanceFilterProvider);
  final sort = ref.watch(availableOrdersSortProvider);

  if (user == null ||
      driver == null ||
      !status.isOnline ||
      status.location == null) {
    return Stream<List<Order>>.value(const <Order>[]);
  }

  final origin = status.location!;
  final repository = ref.watch(orderRepositoryProvider);

  return repository
      .watchAvailableOrders(origin.lat, origin.lng, 50)
      .map((orders) {
    final filtered = orders.where((order) {
      if (order.vehicleType != driver.vehicleType) {
        return false;
      }

      final distanceKm = Geolocator.distanceBetween(
            origin.lat,
            origin.lng,
            order.pickupLocation.lat,
            order.pickupLocation.lng,
          ) /
          1000;

      return switch (filter) {
        AvailableOrdersDistanceFilter.under5km => distanceKm <= 5,
        AvailableOrdersDistanceFilter.under10km => distanceKm <= 10,
        AvailableOrdersDistanceFilter.all => true,
      };
    }).toList();

    filtered.sort((a, b) {
      final distanceA = Geolocator.distanceBetween(
        origin.lat,
        origin.lng,
        a.pickupLocation.lat,
        a.pickupLocation.lng,
      );
      final distanceB = Geolocator.distanceBetween(
        origin.lat,
        origin.lng,
        b.pickupLocation.lat,
        b.pickupLocation.lng,
      );

      return switch (sort) {
        AvailableOrdersSort.price =>
          b.estimatedPrice.compareTo(a.estimatedPrice),
        AvailableOrdersSort.distance => distanceA.compareTo(distanceB),
        AvailableOrdersSort.createdAt => a.createdAt.compareTo(b.createdAt),
      };
    });

    return filtered;
  });
});

final driverHomeAvailableOrdersProvider = Provider<AsyncValue<List<Order>>>((ref) {
  return ref.watch(availableOrdersProvider);
});
