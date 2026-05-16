import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/features/driver/domain/entities/driver.dart' as driver_domain;
import 'package:tow_truck_frontend/features/driver/presentation/providers/driver_provider.dart';
import 'package:tow_truck_frontend/features/map/domain/entities/map_location.dart';
import 'active_order_provider.dart';

class DriverLocation {
  const DriverLocation({
    required this.driverId,
    required this.location,
    required this.heading,
    required this.speed,
    required this.lastUpdated,
  });

  final String driverId;
  final MapLocation location;
  final double heading;
  final double speed;
  final DateTime lastUpdated;

  factory DriverLocation.fromDriver(driver_domain.Driver driver) {
    final currentLocation = driver.currentLocation;
    if (currentLocation == null) {
      throw StateError('Driver location is not available');
    }

    return DriverLocation(
      driverId: driver.userId,
      location: MapLocation(
        latitude: currentLocation.lat,
        longitude: currentLocation.lng,
      ),
      heading: 0,
      speed: 30,
      lastUpdated: DateTime.now(),
    );
  }

  bool get isStale => DateTime.now().difference(lastUpdated).inMinutes > 2;
}

final driverLocationStreamProvider =
    StreamProvider.autoDispose<DriverLocation?>((ref) {
  final driverId = ref.watch(assignedDriverIdProvider);
  if (driverId == null) {
    return Stream<DriverLocation?>.value(null);
  }

  final repository = ref.watch(driverRepositoryProvider);
  return repository.watchDriver(driverId).map((driver) {
    if (driver?.currentLocation == null) {
      return null;
    }
    return DriverLocation.fromDriver(driver!);
  });
});

final driverLocationProvider = Provider<DriverLocation?>((ref) {
  return ref.watch(driverLocationStreamProvider).valueOrNull;
});

final isDriverLocationStaleProvider = Provider<bool>((ref) {
  return ref.watch(driverLocationProvider)?.isStale ?? true;
});

final driverETAProvider = Provider<Duration?>((ref) {
  final driverLocation = ref.watch(driverLocationProvider);
  final activeOrder = ref.watch(activeOrderProvider);
  if (driverLocation == null || activeOrder == null) {
    return null;
  }

  final pickup = MapLocation(
    latitude: activeOrder.pickupLocation.lat,
    longitude: activeOrder.pickupLocation.lng,
    address: activeOrder.pickupLocation.address,
  );
  final distance = _calculateDistance(driverLocation.location, pickup);
  final speed = driverLocation.speed > 5 ? driverLocation.speed : 30.0;
  final timeInMinutes = ((distance / speed) * 60).round().clamp(2, 60);
  return Duration(minutes: timeInMinutes);
});

double _calculateDistance(MapLocation from, MapLocation to) {
  const earthRadius = 6371.0;
  final lat1 = from.latitude * math.pi / 180;
  final lon1 = from.longitude * math.pi / 180;
  final lat2 = to.latitude * math.pi / 180;
  final lon2 = to.longitude * math.pi / 180;
  final dLat = lat2 - lat1;
  final dLon = lon2 - lon1;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadius * c;
}
