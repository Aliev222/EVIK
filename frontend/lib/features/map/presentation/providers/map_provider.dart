import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:tow_truck_frontend/core/services/openstreetmap_service.dart';
import 'package:tow_truck_frontend/features/map/domain/entities/map_location.dart';

class MapState {
  const MapState({
    this.currentPosition,
    this.pickupLocation,
    this.dropoffLocation,
    this.cameraPosition,
    this.zoomLevel = 14.0,
    this.isLoading = false,
    this.error,
    this.permissionGranted = false,
  });

  final MapLocation? currentPosition;
  final MapLocation? pickupLocation;
  final MapLocation? dropoffLocation;
  final MapLocation? cameraPosition;
  final double zoomLevel;
  final bool isLoading;
  final String? error;
  final bool permissionGranted;

  MapState copyWith({
    MapLocation? currentPosition,
    MapLocation? pickupLocation,
    MapLocation? dropoffLocation,
    MapLocation? cameraPosition,
    double? zoomLevel,
    bool? isLoading,
    String? error,
    bool? permissionGranted,
  }) {
    return MapState(
      currentPosition: currentPosition ?? this.currentPosition,
      pickupLocation: pickupLocation ?? this.pickupLocation,
      dropoffLocation: dropoffLocation ?? this.dropoffLocation,
      cameraPosition: cameraPosition ?? this.cameraPosition,
      zoomLevel: zoomLevel ?? this.zoomLevel,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      permissionGranted: permissionGranted ?? this.permissionGranted,
    );
  }
}

class MapNotifier extends StateNotifier<MapState> {
  MapNotifier() : super(const MapState());

  StreamSubscription<Position>? _positionSubscription;

  Future<void> getCurrentLocation() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final permission = await Permission.location.request();
      if (permission.isDenied) {
        state = state.copyWith(
          isLoading: false,
          error: 'Разрешение на геолокацию отклонено',
          permissionGranted: false,
        );
        return;
      }

      final isEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isEnabled) {
        state = state.copyWith(
          isLoading: false,
          error: 'Включите геолокацию в настройках',
          permissionGranted: true,
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      final address = await reverseGeocode(
        position.latitude,
        position.longitude,
      );
      final currentLocation = MapLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        address: address,
      );

      state = state.copyWith(
        currentPosition: currentLocation,
        cameraPosition: currentLocation,
        isLoading: false,
        permissionGranted: true,
      );

      _startLocationTracking();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Ошибка получения местоположения: $e',
      );
    }
  }

  void _startLocationTracking() {
    _positionSubscription?.cancel();

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen(
      (position) async {
        final address = await reverseGeocode(
          position.latitude,
          position.longitude,
        );
        final newLocation = MapLocation(
          latitude: position.latitude,
          longitude: position.longitude,
          address: address,
        );

        state = state.copyWith(currentPosition: newLocation);
      },
      onError: (error) {
        state = state.copyWith(error: 'Ошибка отслеживания: $error');
      },
    );
  }

  void stopLocationTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  void setPickupLocation(MapLocation location) {
    state = state.copyWith(pickupLocation: location);
  }

  void setDropoffLocation(MapLocation location) {
    state = state.copyWith(dropoffLocation: location);
  }

  void moveCamera(MapLocation location, {double? zoom}) {
    state = state.copyWith(
      cameraPosition: location,
      zoomLevel: zoom ?? state.zoomLevel,
    );
  }

  Future<String> reverseGeocode(double latitude, double longitude) async {
    try {
      return await OpenStreetMapService.reverseGeocode(
            lat: latitude,
            lng: longitude,
          ) ??
          'Москва, ${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';
    } catch (e) {
      return 'Неизвестный адрес';
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  void resetLocations() {
    state = state.copyWith(
      pickupLocation: null,
      dropoffLocation: null,
    );
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }
}

final mapProvider = StateNotifierProvider<MapNotifier, MapState>((ref) {
  return MapNotifier();
});

final currentPositionProvider = Provider<MapLocation?>((ref) {
  return ref.watch(mapProvider).currentPosition;
});

final pickupLocationProvider = Provider<MapLocation?>((ref) {
  return ref.watch(mapProvider).pickupLocation;
});

final dropoffLocationProvider = Provider<MapLocation?>((ref) {
  return ref.watch(mapProvider).dropoffLocation;
});

final cameraPositionProvider = Provider<MapLocation?>((ref) {
  return ref.watch(mapProvider).cameraPosition;
});

final mapErrorProvider = Provider<String?>((ref) {
  return ref.watch(mapProvider).error;
});

final locationPermissionProvider = Provider<bool>((ref) {
  return ref.watch(mapProvider).permissionGranted;
});
