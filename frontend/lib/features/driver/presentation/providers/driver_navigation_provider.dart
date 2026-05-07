import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/services/location_service.dart';
import '../../../../core/services/promaps_service.dart';
import '../../../order/domain/entities/order.dart';

class DriverNavigationState {
  const DriverNavigationState({
    this.currentRoute = const <LocationModel>[],
    this.eta,
    this.distanceKm,
    this.isNavigating = false,
    this.errorMessage,
  });

  final List<LocationModel> currentRoute;
  final Duration? eta;
  final double? distanceKm;
  final bool isNavigating;
  final String? errorMessage;

  DriverNavigationState copyWith({
    List<LocationModel>? currentRoute,
    Duration? eta,
    double? distanceKm,
    bool? isNavigating,
    String? errorMessage,
  }) {
    return DriverNavigationState(
      currentRoute: currentRoute ?? this.currentRoute,
      eta: eta ?? this.eta,
      distanceKm: distanceKm ?? this.distanceKm,
      isNavigating: isNavigating ?? this.isNavigating,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class DriverNavigationNotifier extends StateNotifier<DriverNavigationState> {
  DriverNavigationNotifier() : super(const DriverNavigationState());

  final LocationService _locationService = LocationService.instance;

  Future<void> buildRouteToClient(Order order, LocationModel from) async {
    await _buildRoute(from: from, to: order.pickupLocation);
  }

  Future<void> buildRouteToDropoff(Order order, LocationModel from) async {
    await _buildRoute(from: from, to: order.dropoffLocation);
  }

  Future<void> _buildRoute({
    required LocationModel from,
    required LocationModel to,
  }) async {
    final distance = await _locationService.calculateRouteDistance(
      from: from,
      to: to,
    );
    final etaMinutes = await _locationService.calculateEstimatedTime(
      from: from,
      to: to,
    );

    state = state.copyWith(
      currentRoute: <LocationModel>[from, to],
      distanceKm: distance,
      eta: etaMinutes == null ? null : Duration(minutes: etaMinutes),
      isNavigating: true,
      errorMessage: null,
    );
  }

  Future<void> openProMapsNavigation(double lat, double lng) async {
    final uri = Uri.parse(
      ProMapsService.getEmbedMapUrl(lat: lat, lng: lng, zoom: 16),
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
  }

  Future<void> trackDriverPosition() async {
    state = state.copyWith(isNavigating: true);
  }

  Future<Duration?> calculateETA(LocationModel from, LocationModel to) async {
    final minutes = await _locationService.calculateEstimatedTime(
      from: from,
      to: to,
    );
    return minutes == null ? null : Duration(minutes: minutes);
  }
}

final driverNavigationProvider =
    StateNotifierProvider<DriverNavigationNotifier, DriverNavigationState>(
        (ref) {
  return DriverNavigationNotifier();
});
