import 'dart:async';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/promaps_service.dart';
import '../../../../core/services/realtime_location_service.dart';
import '../../../order/domain/entities/order.dart';
import '../../../map/presentation/widgets/animated_driver_marker.dart';

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
  final ProMapsRoute? route;
  final DateTime? estimatedArrival;
  final DriverMarkerStatus status;
  final bool isTracking;
  final String? error;

  RealTimeDriverState copyWith({
    LocationModel? driverLocation,
    ProMapsRoute? route,
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
  RealTimeDriverNotifier(this._realTimeService) : super(const RealTimeDriverState()) {
    _initializeRealTimeConnection();
  }

  final RealTimeLocationService _realTimeService;
  Timer? _trackingTimer;
  String? _activeOrderId;
  StreamSubscription? _driverLocationSubscription;
  StreamSubscription? _orderUpdateSubscription;

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

  /// Start tracking driver for specific order
  Future<void> startTracking(String orderId, LocationModel destination) async {
    _activeOrderId = orderId;

    state = state.copyWith(
      isTracking: true,
      error: null,
    );

    // Подключаемся к WebSocket серверу как клиент
    final connected = await _realTimeService.connect(
      userId: orderId, // Используем orderId как уникальный идентификатор
      userType: 'client',
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
}

/// Provider for real-time driver tracking
final realTimeDriverProvider = StateNotifierProvider<RealTimeDriverNotifier, RealTimeDriverState>((ref) {
  final realTimeService = ref.read(realTimeLocationServiceProvider);
  return RealTimeDriverNotifier(realTimeService);
});

/// Provider for multiple drivers tracking (for admin)
final adminDriversTrackingProvider = StreamProvider<List<DriverTrackingInfo>>((ref) {
  return Stream.periodic(
    const Duration(seconds: 5),
    (_) => _generateMockDrivers(),
  );
});

/// Generate mock drivers for admin panel
List<DriverTrackingInfo> _generateMockDrivers() {
  final now = DateTime.now();
  final baseTime = now.millisecondsSinceEpoch / 1000000;

  return [
    DriverTrackingInfo(
      id: 'driver_1',
      name: 'Алексей Иванов',
      vehicle: 'ГАЗель Next',
      location: LocationModel(
        lat: 55.7558 + sin(baseTime) * 0.01,
        lng: 37.6173 + cos(baseTime) * 0.01,
        address: 'В движении',
      ),
      status: DriverMarkerStatus.toPickup,
      speed: 45,
      lastUpdate: now.subtract(const Duration(seconds: 2)),
    ),
    DriverTrackingInfo(
      id: 'driver_2',
      name: 'Дмитрий Петров',
      vehicle: 'Ford Transit',
      location: LocationModel(
        lat: 55.7422 + cos(baseTime * 1.5) * 0.008,
        lng: 37.6156 + sin(baseTime * 1.5) * 0.008,
        address: 'В движении',
      ),
      status: DriverMarkerStatus.toDestination,
      speed: 38,
      lastUpdate: now.subtract(const Duration(seconds: 1)),
    ),
    DriverTrackingInfo(
      id: 'driver_3',
      name: 'Сергей Козлов',
      vehicle: 'Mercedes Sprinter',
      location: LocationModel(
        lat: 55.7811 + sin(baseTime * 0.8) * 0.012,
        lng: 37.6092 + cos(baseTime * 0.8) * 0.012,
        address: 'В движении',
      ),
      status: DriverMarkerStatus.waiting,
      speed: 0,
      lastUpdate: now.subtract(const Duration(seconds: 3)),
    ),
  ];
}

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