import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'package:tow_truck_frontend/core/network/api_client_stub.dart'
    if (dart.library.io) '../../../core/network/api_client_io.dart'
    as platform_api;

class ServiceAreaState {
  final bool isChecking;
  final bool isChecked;
  final bool isAllowed;
  final String? cityName;
  final double? lastCheckedLat;
  final double? lastCheckedLng;

  const ServiceAreaState({
    this.isChecking = false,
    this.isChecked = false,
    this.isAllowed = true,
    this.cityName,
    this.lastCheckedLat,
    this.lastCheckedLng,
  });

  ServiceAreaState copyWith({
    bool? isChecking,
    bool? isChecked,
    bool? isAllowed,
    String? cityName,
    bool clearCityName = false,
    double? lastCheckedLat,
    double? lastCheckedLng,
  }) {
    return ServiceAreaState(
      isChecking: isChecking ?? this.isChecking,
      isChecked: isChecked ?? this.isChecked,
      isAllowed: isAllowed ?? this.isAllowed,
      cityName: clearCityName ? null : cityName ?? this.cityName,
      lastCheckedLat: lastCheckedLat ?? this.lastCheckedLat,
      lastCheckedLng: lastCheckedLng ?? this.lastCheckedLng,
    );
  }
}

class ServiceAreaNotifier extends StateNotifier<ServiceAreaState> {
  ServiceAreaNotifier() : super(const ServiceAreaState());

  static const double _cacheInvalidationKm = 10.0;

  Future<void> checkServiceArea(double lat, double lng) async {
    if (state.lastCheckedLat != null && state.lastCheckedLng != null) {
      final distance = Geolocator.distanceBetween(
        state.lastCheckedLat!,
        state.lastCheckedLng!,
        lat,
        lng,
      );
      if (distance < _cacheInvalidationKm * 1000) return;
    }

    state = state.copyWith(isChecking: true);

    try {
      final api = platform_api.createPlatformApiClient();
      final response = await api.get(
        '/api/v1/service-areas/check?lat=$lat&lng=$lng',
      );
      final allowed = response['allowed'] == true;
      final area = response['service_area'] as Map<String, dynamic>?;

      state = ServiceAreaState(
        isChecked: true,
        isAllowed: allowed,
        cityName: area?['name']?.toString(),
        lastCheckedLat: lat,
        lastCheckedLng: lng,
      );
    } catch (_) {
      state = state.copyWith(isChecking: false);
    }
  }

  void reset() {
    state = const ServiceAreaState();
  }
}

final serviceAreaProvider =
    StateNotifierProvider<ServiceAreaNotifier, ServiceAreaState>((ref) {
  return ServiceAreaNotifier();
});
