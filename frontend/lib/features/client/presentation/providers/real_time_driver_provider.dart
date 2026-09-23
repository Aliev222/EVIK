import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/network/api_client_stub.dart'
    if (dart.library.io) 'package:tow_truck_frontend/core/network/api_client_io.dart'
    as platform_api;
import 'package:tow_truck_frontend/core/services/realtime_location_service.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/features/map/presentation/widgets/animated_driver_marker.dart';

const Object _notProvided = Object();

/// Real-time driver tracking for client
class RealTimeDriverState {
  const RealTimeDriverState({
    this.driverLocation,
    this.latestUpdate,
    this.estimatedArrival,
    this.status = DriverMarkerStatus.toPickup,
    this.isTracking = false,
    this.connectionStatus = 'disconnected',
    this.error,
  });

  final LocationModel? driverLocation;
  final DriverLocationUpdate? latestUpdate;
  final DateTime? estimatedArrival;
  final DriverMarkerStatus status;
  final bool isTracking;
  final String connectionStatus;
  final String? error;

  RealTimeDriverState copyWith({
    LocationModel? driverLocation,
    DriverLocationUpdate? latestUpdate,
    DateTime? estimatedArrival,
    DriverMarkerStatus? status,
    bool? isTracking,
    String? connectionStatus,
    Object? error = _notProvided,
  }) {
    return RealTimeDriverState(
      driverLocation: driverLocation ?? this.driverLocation,
      latestUpdate: latestUpdate ?? this.latestUpdate,
      estimatedArrival: estimatedArrival ?? this.estimatedArrival,
      status: status ?? this.status,
      isTracking: isTracking ?? this.isTracking,
      connectionStatus: connectionStatus ?? this.connectionStatus,
      error: identical(error, _notProvided) ? this.error : error as String?,
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
  StreamSubscription<String>? _connectionSubscription;
  String? _activeDriverId;

  @override
  void dispose() {
    _trackingTimer?.cancel();
    _driverLocationSubscription?.cancel();
    _orderUpdateSubscription?.cancel();
    _connectionSubscription?.cancel();
    // This service is shared by the app provider; a client tracking widget
    // must not close its streams for another consumer.
    _realTimeService.disconnect();
    super.dispose();
  }

  /// The provider is the one owner of the client tracking session. Screens
  /// consume its state; they never create a second raw location subscription.
  void _initializeRealTimeConnection() {
    // Слушаем обновления местоположения водителей
    _driverLocationSubscription = _realTimeService.driverLocationStream.listen(
      _handleDriverLocationUpdate,
    );

    // Слушаем обновления заказов
    _orderUpdateSubscription = _realTimeService.orderUpdateStream.listen(
      _handleOrderUpdate,
    );
    _connectionSubscription = _realTimeService.connectionStream.listen(
      (status) {
        if (_activeOrderId == null) return;
        state = state.copyWith(
          connectionStatus: status,
          error: status == 'connected' ? null : state.error,
        );
      },
    );
  }

  /// Обработка обновлений местоположения водителя от WebSocket
  void _handleDriverLocationUpdate(DriverLocationUpdate update) {
    if (_activeOrderId != null &&
        update.orderId == _activeOrderId &&
        (_activeDriverId == null || update.driverId == _activeDriverId)) {
      state = state.copyWith(
        driverLocation: update.location,
        latestUpdate: update,
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
              latestUpdate: update.driver,
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
        case OrderUpdateType.orderCompleted:
        case OrderUpdateType.orderCancelled:
          stopTracking();
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
    String? driverId,
    DriverMarkerStatus initialStatus = DriverMarkerStatus.toPickup,
  }) async {
    if (_activeOrderId == orderId && state.isTracking) {
      final newlyKnownDriver =
          (_activeDriverId == null || _activeDriverId!.isEmpty) &&
              driverId != null &&
              driverId.isNotEmpty;
      if (driverId != null && driverId.isNotEmpty) {
        _activeDriverId = driverId;
      }
      if (newlyKnownDriver && state.latestUpdate == null) {
        unawaited(_restoreLastKnownLocation(
          orderId: orderId,
          driverId: driverId,
          accessToken: accessToken ?? '',
          status: initialStatus,
        ));
      }
      return;
    }
    if (_activeOrderId != null && _activeOrderId != orderId) {
      await _realTimeService.disconnect();
      state = const RealTimeDriverState();
    }
    _activeOrderId = orderId;
    _activeDriverId = driverId;
    // Target routing is owned by TrackingScreen until the backend delivers a
    // canonical route session. Do not start a second unused preview here.

    state = const RealTimeDriverState().copyWith(
      isTracking: true,
      connectionStatus: 'connecting',
      error: null,
    );

    if (driverId != null && driverId.isNotEmpty) {
      unawaited(_restoreLastKnownLocation(
        orderId: orderId,
        driverId: driverId,
        accessToken: accessToken ?? '',
        status: initialStatus,
      ));
    }

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

  Future<void> _restoreLastKnownLocation({
    required String orderId,
    required String driverId,
    required String accessToken,
    required DriverMarkerStatus status,
  }) async {
    try {
      final response = await platform_api.createPlatformApiClient().get(
            '/api/v1/drivers/$driverId/location',
            headers: accessToken.isEmpty
                ? null
                : <String, String>{'Authorization': 'Bearer $accessToken'},
          );
      if (_activeOrderId != orderId) return;
      final raw = response['location'];
      if (raw is! Map<String, dynamic>) return;
      final lat = (raw['lat'] as num?)?.toDouble();
      final lng = (raw['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return;
      final sampledAt =
          DateTime.tryParse(raw['updated_at']?.toString() ?? '') ??
              DateTime.now();
      final current = state.latestUpdate;
      if (current != null && !sampledAt.isAfter(current.timestamp)) return;
      final update = DriverLocationUpdate(
        driverId: driverId,
        lat: lat,
        lng: lng,
        bearing: current?.bearing ?? 0,
        speed: current?.speed ?? 0,
        status: current?.status ?? status,
        orderId: orderId,
        timestamp: sampledAt,
      );
      state = state.copyWith(
        driverLocation: update.location,
        latestUpdate: update,
        status: update.status,
      );
    } catch (_) {
      // Live tracking remains usable when the non-blocking snapshot is absent.
    }
  }

  /// Stop tracking
  void stopTracking() {
    _trackingTimer?.cancel();
    _activeOrderId = null;
    _activeDriverId = null;

    // Отключаемся от WebSocket
    _realTimeService.disconnect();

    // `copyWith` deliberately keeps nullable values for incremental updates;
    // a terminal session needs an explicit fresh state so coordinates cannot
    // bleed into the next order.
    state = const RealTimeDriverState();
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
