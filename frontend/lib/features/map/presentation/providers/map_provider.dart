import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../domain/entities/map_location.dart';

// Состояние карты
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

// Провайдер для управления состоянием карты
class MapNotifier extends StateNotifier<MapState> {
  MapNotifier() : super(const MapState());

  StreamSubscription<Position>? _positionSubscription;

  // Получить текущее GPS местоположение
  Future<void> getCurrentLocation() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      // Проверить разрешения
      final permission = await Permission.location.request();
      if (permission.isDenied) {
        state = state.copyWith(
          isLoading: false,
          error: 'Разрешение на геолокацию отклонено',
          permissionGranted: false,
        );
        return;
      }

      // Проверить включена ли геолокация
      final isEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isEnabled) {
        state = state.copyWith(
          isLoading: false,
          error: 'Включите геолокацию в настройках',
          permissionGranted: true,
        );
        return;
      }

      // Получить текущую позицию
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      final currentLocation = MapLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        address: 'Моё местоположение',
      );

      state = state.copyWith(
        currentPosition: currentLocation,
        cameraPosition: currentLocation,
        isLoading: false,
        permissionGranted: true,
      );

      // Запустить отслеживание позиции
      _startLocationTracking();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Ошибка получения местоположения: $e',
      );
    }
  }

  // Запустить отслеживание позиции в реальном времени
  void _startLocationTracking() {
    _positionSubscription?.cancel();

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // минимальная дистанция для обновления (метры)
      ),
    ).listen(
      (position) {
        final newLocation = MapLocation(
          latitude: position.latitude,
          longitude: position.longitude,
          address: 'Моё местоположение',
        );

        state = state.copyWith(currentPosition: newLocation);
      },
      onError: (error) {
        state = state.copyWith(error: 'Ошибка отслеживания: $error');
      },
    );
  }

  // Остановить отслеживание позиции
  void stopLocationTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  // Установить точку забора
  void setPickupLocation(MapLocation location) {
    state = state.copyWith(pickupLocation: location);
  }

  // Установить точку доставки
  void setDropoffLocation(MapLocation location) {
    state = state.copyWith(dropoffLocation: location);
  }

  // Переместить камеру
  void moveCamera(MapLocation location, {double? zoom}) {
    state = state.copyWith(
      cameraPosition: location,
      zoomLevel: zoom ?? state.zoomLevel,
    );
  }

  // Обратное геокодирование - получить адрес по координатам
  Future<String> reverseGeocode(double latitude, double longitude) async {
    try {
      // Здесь должен быть вызов к Yandex Geocoder API
      // Пока возвращаем заглушку
      return 'ул. Примерная, д. ${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';
    } catch (e) {
      return 'Неизвестный адрес';
    }
  }

  // Очистить ошибки
  void clearError() {
    state = state.copyWith(error: null);
  }

  // Сброс всех локаций
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

// Провайдеры для Riverpod
final mapProvider = StateNotifierProvider<MapNotifier, MapState>((ref) {
  return MapNotifier();
});

// Провайдеры для отдельных частей состояния
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
