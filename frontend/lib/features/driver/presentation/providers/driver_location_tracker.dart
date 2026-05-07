import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/location_service.dart';
import '../../../../core/services/promaps_service.dart';
import '../../../order/domain/entities/order.dart';

/// Real-time driver location tracking
class DriverLocationTracker extends StateNotifier<DriverLocationState> {
  DriverLocationTracker() : super(const DriverLocationState());

  Timer? _locationUpdateTimer;
  final LocationService _locationService = LocationService.instance;

  @override
  void dispose() {
    _locationUpdateTimer?.cancel();
    super.dispose();
  }

  /// Start tracking driver location for an active order
  Future<void> startTracking(String orderId) async {
    state = state.copyWith(isTracking: true, orderId: orderId);

    // Update location every 10 seconds
    _locationUpdateTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _updateLocation(),
    );

    // Initial location update
    await _updateLocation();
  }

  /// Stop tracking
  void stopTracking() {
    _locationUpdateTimer?.cancel();
    state = state.copyWith(
      isTracking: false,
      orderId: null,
      currentLocation: null,
    );
  }

  /// Update current location and send to backend
  Future<void> _updateLocation() async {
    try {
      final currentLocation = await _locationService.getCurrentLocation();

      if (currentLocation == null) {
        state = state.copyWith(
          error: 'Не удалось получить местоположение',
        );
        return;
      }

      state = state.copyWith(
        currentLocation: currentLocation,
        lastUpdate: DateTime.now(),
        error: null,
      );

      // TODO: Send location update to backend API
      // await DriverApiClient.updateLocation(
      //   orderId: state.orderId!,
      //   lat: currentLocation.lat,
      //   lng: currentLocation.lng,
      // );

    } catch (e) {
      state = state.copyWith(
        error: 'Ошибка обновления местоположения: $e',
      );
    }
  }

  /// Calculate ETA to pickup/dropoff using ProMaps
  Future<Duration?> calculateETA(LocationModel destination) async {
    final currentLocation = state.currentLocation;
    if (currentLocation == null) return null;

    try {
      final route = await ProMapsService.getRoute(
        fromLat: currentLocation.lat,
        fromLng: currentLocation.lng,
        toLat: destination.lat,
        toLng: destination.lng,
        profile: 'driving',
      );

      return route != null
        ? Duration(minutes: route.durationMinutes.round())
        : null;

    } catch (e) {
      return null;
    }
  }

  /// Get route to destination using ProMaps
  Future<ProMapsRoute?> getRouteToDestination(LocationModel destination) async {
    final currentLocation = state.currentLocation;
    if (currentLocation == null) return null;

    try {
      return await ProMapsService.getRoute(
        fromLat: currentLocation.lat,
        fromLng: currentLocation.lng,
        toLat: destination.lat,
        toLng: destination.lng,
        profile: 'driving',
      );
    } catch (e) {
      return null;
    }
  }
}

class DriverLocationState {
  const DriverLocationState({
    this.isTracking = false,
    this.orderId,
    this.currentLocation,
    this.lastUpdate,
    this.error,
  });

  final bool isTracking;
  final String? orderId;
  final LocationModel? currentLocation;
  final DateTime? lastUpdate;
  final String? error;

  DriverLocationState copyWith({
    bool? isTracking,
    String? orderId,
    LocationModel? currentLocation,
    DateTime? lastUpdate,
    String? error,
  }) {
    return DriverLocationState(
      isTracking: isTracking ?? this.isTracking,
      orderId: orderId ?? this.orderId,
      currentLocation: currentLocation ?? this.currentLocation,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      error: error ?? this.error,
    );
  }
}

/// Provider for driver location tracking
final driverLocationTrackerProvider = StateNotifierProvider<DriverLocationTracker, DriverLocationState>((ref) {
  return DriverLocationTracker();
});

/// Provider for client to track driver location
final clientDriverLocationProvider = StreamProvider.family<LocationModel?, String>((ref, orderId) {
  // This would listen to real-time updates from the backend
  // For now, return a stream that updates every 5 seconds
  return Stream.periodic(
    const Duration(seconds: 5),
    (_) => LocationModel(
      lat: 55.7558 + (DateTime.now().millisecond / 1000000), // Simulate movement
      lng: 37.6173 + (DateTime.now().millisecond / 1000000),
      address: 'Движется к вам...',
    ),
  ).take(100); // Limit to 100 updates
});