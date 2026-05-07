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
    try {
      // Use ProMaps for route calculation
      final route = await ProMapsService.getRoute(
        fromLat: from.lat,
        fromLng: from.lng,
        toLat: to.lat,
        toLng: to.lng,
        profile: 'driving',
      );

      if (route != null) {
        state = state.copyWith(
          currentRoute: <LocationModel>[from, to],
          distanceKm: route.distanceKm,
          eta: Duration(minutes: route.durationMinutes.round()),
          isNavigating: true,
          errorMessage: null,
        );
      } else {
        state = state.copyWith(
          errorMessage: 'Не удалось построить маршрут',
          isNavigating: false,
        );
      }
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Ошибка построения маршрута: $e',
        isNavigating: false,
      );
    }
  }

  Future<void> openProMapsNavigator(double lat, double lng) async {
    // Try to open in external navigation apps first
    final googleMapsUri = Uri.parse('google.navigation:q=$lat,$lng');
    final yandexNaviUri = Uri.parse('yandexnavi://build_route_on_map?lat_to=$lat&lon_to=$lng');

    // Try Google Maps first
    if (await canLaunchUrl(googleMapsUri)) {
      await launchUrl(googleMapsUri);
      return;
    }

    // Try Yandex Navigator
    if (await canLaunchUrl(yandexNaviUri)) {
      await launchUrl(yandexNaviUri);
      return;
    }

    // Fallback to web ProMaps
    final webFallback = Uri.parse('https://maps.google.com/maps?daddr=$lat,$lng');
    await launchUrl(webFallback, mode: LaunchMode.externalApplication);
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
