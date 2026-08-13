import 'dart:async';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/constants/app_constants.dart';
import 'package:tow_truck_frontend/core/services/openstreetmap_service.dart';
import 'package:tow_truck_frontend/core/services/realtime_location_service.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/features/map/presentation/widgets/animated_driver_marker.dart';

/// Real-time driver tracking for client
class RealTimeDriverState {
  const RealTimeDriverState({
    this.driverLocation,
    this.route,
    this.estimatedArrival,
    this.status = DriverMarkerStatus.toPickup,
    this.isTracking = false,
    this.error,
  });

  final LocationModel? driverLocation;
  final RoutePreview? route;
  final DateTime? estimatedArrival;
  final DriverMarkerStatus status;
  final bool isTracking;
  final String? error;

  RealTimeDriverState copyWith({
    LocationModel? driverLocation,
    RoutePreview? route,
    DateTime? estimatedArrival,
    DriverMarkerStatus? status,
    bool? isTracking,
    String? error,
  }) {
    return RealTimeDriverState(
      driverLocation: driverLocation ?? this.driverLocation,
      route: route ?? this.route,
      estimatedArrival: estimatedArrival ?? this.estimatedArrival,
      status: status ?? this.status,
      isTracking: isTracking ?? this.isTracking,
      error: error ?? this.error,
    );
  }
}

class RealTimeDriverNotifier extends StateNotifier<RealTimeDriverState> {
  RealTimeDriverNotifier(this._realTimeService)
      : super(const RealTimeDriverState()) {
    _initializeRealTimeConnection();
  }

  final RealTimeLocationService _realTimeService;
  Timer? _trackingTimer;
  String? _activeOrderId;
  StreamSubscription? _driverLocationSubscription;
  StreamSubscription? _orderUpdateSubscription;
  LocationModel? _destination;
  LocationModel? _lastRouteDriverLocation;

  @override
  void dispose() {
    _trackingTimer?.cancel();
    _driverLocationSubscription?.cancel();
    _orderUpdateSubscription?.cancel();
    _realTimeService.dispose();
    super.dispose();
  }

  /// Инициализация real-time соединения
  void _initializeRealTimeConnection() {
    // Слушаем обновления местоположения водителей
    _driverLocationSubscription = _realTimeService.driverLocationStream.listen(
      _handleDriverLocationUpdate,
    );

    // Слушаем обновления заказов
    _orderUpdateSubscription = _realTimeService.orderUpdateStream.listen(
      _handleOrderUpdate,
    );
  }

  /// Обработка обновлений местоположения водителя от WebSocket
  void _handleDriverLocationUpdate(DriverLocationUpdate update) {
    if (_activeOrderId != null && update.orderId == _activeOrderId) {
      state = state.copyWith(
        driverLocation: update.location,
        status: update.status,
        error: null,
      );
      _refreshRoutePreviewIfNeeded(update.location);
    }
  }

  /// Обработка обновлений заказов от WebSocket
  void _handleOrderUpdate(OrderUpdate update) {
    if (update.orderId == _activeOrderId) {
      switch (update.status) {
        case OrderUpdateType.driverFound:
          if (update.driver != null) {
            state = state.copyWith(
              driverLocation: update.driver!.location,
              status: update.driver!.status,
              error: null,
            );
            _refreshRoutePreviewIfNeeded(update.driver!.location);
          }
          break;
        case OrderUpdateType.noDriversAvailable:
          state = state.copyWith(
            error: update.message ?? 'Водители недоступны',
            isTracking: false,
          );
          break;
        default:
          break;
      }
    }
  }

  /// Start tracking driver for specific order.
  ///
  /// [userId] and [accessToken] identify the authenticated client so the
  /// server can address events of this order to this client (the backend
  /// delivers EventDriverLocationUpdated to the order's user_id from the JWT).
  Future<void> startTracking(
    String orderId,
    LocationModel destination, {
    String? userId,
    String? accessToken,
  }) async {
    _activeOrderId = orderId;
    _destination = destination;
    _lastRouteDriverLocation = null;

    state = state.copyWith(
      isTracking: true,
      error: null,
    );

    // Подключаемся к WebSocket серверу как авторизованный клиент.
    final hasUserId = userId != null && userId.isNotEmpty;
    final connected = await _realTimeService.connect(
      userId: hasUserId ? userId : orderId,
      userType: 'client',
      accessToken: accessToken ?? '',
    );

    if (!connected) {
      state = state.copyWith(
        error: 'Не удалось подключиться к серверу отслеживания',
        isTracking: false,
      );
      return;
    }

    // Real-time обновления приходят через WebSocket stream
    // Больше не нужен таймер для симуляции
  }

  /// Stop tracking
  void stopTracking() {
    _trackingTimer?.cancel();
    _activeOrderId = null;

    // Отключаемся от WebSocket
    _realTimeService.disconnect();
    _destination = null;
    _lastRouteDriverLocation = null;

    state = state.copyWith(
      isTracking: false,
      driverLocation: null,
      route: null,
      estimatedArrival: null,
    );
  }

  /// Update driver status (pickup -> destination)
  void updateDriverStatus(DriverMarkerStatus newStatus) {
    state = state.copyWith(status: newStatus);
  }

  /// Get formatted ETA string
  String? get formattedETA {
    if (state.estimatedArrival == null) return null;

    final now = DateTime.now();
    final difference = state.estimatedArrival!.difference(now);

    if (difference.isNegative) return 'Прибыл';

    final minutes = difference.inMinutes;
    if (minutes < 1) return 'Меньше минуты';
    if (minutes < 60) return '$minutes мин';

    final hours = difference.inHours;
    final remainingMinutes = minutes % 60;
    return '$hours ч $remainingMinutes мин';
  }

  /// Get distance to destination in km
  double? get distanceKm {
    return state.route?.distanceKm;
  }

  Future<void> _refreshRoutePreviewIfNeeded(
      LocationModel driverLocation) async {
    final destination = _destination;
    if (destination == null) return;

    final last = _lastRouteDriverLocation;
    if (last != null &&
        _distanceMeters(last, driverLocation) <
            AppConstants.clientRouteRefreshThresholdM) {
      return;
    }
    _lastRouteDriverLocation = driverLocation;

    final route = await OpenStreetMapService.getRoutePreview(
      fromLat: driverLocation.lat,
      fromLng: driverLocation.lng,
      toLat: destination.lat,
      toLng: destination.lng,
    );
    if (route == null || _activeOrderId == null) return;

    state = state.copyWith(
      route: route,
      estimatedArrival: DateTime.now().add(
        Duration(seconds: route.durationSeconds.round()),
      ),
    );
  }

  double _distanceMeters(LocationModel a, LocationModel b) {
    const earthRadiusM = 6371000.0;
    final dLat = _radians(b.lat - a.lat);
    final dLng = _radians(b.lng - a.lng);
    final lat1 = _radians(a.lat);
    final lat2 = _radians(b.lat);
    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2);
    return 2 * earthRadiusM * atan2(sqrt(h), sqrt(1 - h));
  }

  double _radians(double degrees) => degrees * pi / 180;
}

/// Provider for real-time driver tracking
final realTimeDriverProvider =
    StateNotifierProvider<RealTimeDriverNotifier, RealTimeDriverState>((ref) {
  final realTimeService = ref.read(realTimeLocationServiceProvider);
  return RealTimeDriverNotifier(realTimeService);
});

/// Provider for multiple drivers tracking (for admin)
final adminDriversTrackingProvider =
    StreamProvider<List<DriverTrackingInfo>>((ref) {
  return Stream.periodic(
    const Duration(seconds: 5),
    (_) => <DriverTrackingInfo>[],
  );
});

/// Driver tracking info for admin panel
class DriverTrackingInfo {
  const DriverTrackingInfo({
    required this.id,
    required this.name,
    required this.vehicle,
    required this.location,
    required this.status,
    required this.speed,
    required this.lastUpdate,
  });

  final String id;
  final String name;
  final String vehicle;
  final LocationModel location;
  final DriverMarkerStatus status;
  final double speed; // km/h
  final DateTime lastUpdate;
}
