import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'package:tow_truck_frontend/core/services/realtime_location_service.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/features/map/presentation/widgets/animated_driver_marker.dart';
import 'package:tow_truck_frontend/features/driver/data/services/driver_location_service.dart';

/// Состояние водителя для real-time отслеживания
class DriverRealTimeState {
  const DriverRealTimeState({
    this.isOnline = false,
    this.isConnected = false,
    this.currentLocation,
    this.currentOrder,
    this.status = DriverMarkerStatus.waiting,
    this.speed = 0.0,
    this.bearing = 0.0,
    this.accuracyM,
    this.sampledAt,
    this.error,
  });

  final bool isOnline;
  final bool isConnected;
  final LocationModel? currentLocation;
  final String? currentOrder;
  final DriverMarkerStatus status;
  final double speed;
  final double bearing;
  final double? accuracyM;
  final DateTime? sampledAt;
  final String? error;

  DriverRealTimeState copyWith({
    bool? isOnline,
    bool? isConnected,
    LocationModel? currentLocation,
    String? currentOrder,
    bool clearCurrentOrder = false,
    DriverMarkerStatus? status,
    double? speed,
    double? bearing,
    double? accuracyM,
    DateTime? sampledAt,
    String? error,
  }) {
    return DriverRealTimeState(
      isOnline: isOnline ?? this.isOnline,
      isConnected: isConnected ?? this.isConnected,
      currentLocation: currentLocation ?? this.currentLocation,
      currentOrder:
          clearCurrentOrder ? null : currentOrder ?? this.currentOrder,
      status: status ?? this.status,
      speed: speed ?? this.speed,
      bearing: bearing ?? this.bearing,
      accuracyM: accuracyM ?? this.accuracyM,
      sampledAt: sampledAt ?? this.sampledAt,
      error: error ?? this.error,
    );
  }
}

/// Real-time провайдер для водителя (отправка GPS координат)
class DriverRealTimeNotifier extends StateNotifier<DriverRealTimeState> {
  DriverRealTimeNotifier(this._realTimeService,
      {DriverLocationService? locationService})
      : _locationService = locationService ?? DriverLocationService(),
        super(const DriverRealTimeState()) {
    _initializeServices();
  }

  final RealTimeLocationService _realTimeService;
  final DriverLocationService _locationService;
  bool _sendingLocation = false;

  Timer? _locationTimer;
  StreamSubscription<String>? _connectionSubscription;
  StreamSubscription? _orderUpdateSubscription;
  String? _driverId;

  @override
  void dispose() {
    _locationTimer?.cancel();
    _connectionSubscription?.cancel();
    _orderUpdateSubscription?.cancel();
    _locationService.dispose();
    super.dispose();
  }

  void _initializeServices() {
    // Слушаем обновления заказов
    _orderUpdateSubscription = _realTimeService.orderUpdateStream.listen(
      _handleOrderUpdate,
    );
    // Слушаем статус соединения для авто-обновления isConnected после реконнекта
    _connectionSubscription =
        _realTimeService.connectionStream.listen((status) {
      if (status == 'connected') {
        state = state.copyWith(isConnected: true);
      } else if (status == 'disconnected' || status == 'connection_failed') {
        state = state.copyWith(isConnected: false);
      }
    });
  }

  /// Подключение водителя к real-time системе
  Future<bool> connectAsDriver(String driverId,
      {required String accessToken}) async {
    _driverId = driverId;

    final connected = await _realTimeService.connect(
      userId: driverId,
      userType: 'driver',
      accessToken: accessToken,
    );

    state = state.copyWith(
      isConnected: connected,
      error: connected ? null : 'Ошибка подключения к серверу',
    );

    return connected;
  }

  /// Начало смены водителя (статус онлайн)
  Future<void> goOnline() async {
    if (!state.isConnected || _driverId == null) {
      state = state.copyWith(error: 'Нет соединения с сервером');
      return;
    }

    // Получаем текущее местоположение (сырые GPS-координаты без reverse-geocode)
    try {
      await _locationService.checkPermissions(requireBackground: true);
      final position = await _locationService.getCurrentPosition();
      if (!mounted) return;
      final location = _locationFromPosition(position);
      await _locationService.startLocationTracking(
        driverId: _driverId!,
        interval: const Duration(seconds: 3),
        onPosition: (position) {
          if (!mounted || !state.isOnline) return;
          state = state.copyWith(
            currentLocation: _locationFromPosition(position),
            speed: position.speed.isFinite && position.speed > 0
                ? position.speed * 3.6
                : 0,
            bearing: position.heading.isFinite && position.heading >= 0
                ? position.heading
                : state.bearing,
            accuracyM: position.accuracy.isFinite ? position.accuracy : null,
            sampledAt: position.timestamp,
          );
          unawaited(_sendLocationUpdate());
        },
        onError: (_) {
          if (mounted) {
            state = state.copyWith(
                error: 'Геолокация остановлена. Проверьте разрешения.');
          }
        },
      );
      if (!mounted) return;
      state = state.copyWith(
        isOnline: true,
        currentLocation: location,
        accuracyM: position.accuracy.isFinite ? position.accuracy : null,
        sampledAt: position.timestamp,
        status: state.currentOrder == null
            ? DriverMarkerStatus.waiting
            : state.status,
        error: null,
      );
    } catch (error) {
      if (mounted) state = state.copyWith(error: '$error');
      return;
    }

    // Отправляем начальную позицию
    await _sendLocationUpdate();

    // Начинаем отправлять GPS координаты. Частота адаптивная:
    // в активном заказе — чаще (клиент следит за маркером), в ожидании — реже
    // (меньше трафика и нагрузки на сервер).
    _startLocationTimer();
  }

  /// Адаптивная отправка геолокации: в заказе каждые 3 сек, в ожидании — 10 сек.
  void _startLocationTimer() {
    _locationTimer?.cancel();
    if (!state.isOnline) return;
    final interval = state.currentOrder != null
        ? const Duration(seconds: 3)
        : const Duration(seconds: 10);
    _locationTimer = Timer.periodic(interval, (_) => _sendLocationUpdate());
  }

  /// Завершение смены водителя (статус оффлайн)
  Future<void> goOffline() async {
    _locationTimer?.cancel();
    await _locationService.stopLocationTracking();
    if (!mounted) return;

    state = state.copyWith(
      isOnline: false,
      status: DriverMarkerStatus.waiting,
    );

    await _realTimeService.disconnect();

    state = state.copyWith(isConnected: false);
  }

  /// Восстановление заказа после перезапуска приложения
  void restoreOrder(String orderId, DriverMarkerStatus status) {
    state = state.copyWith(
      currentOrder: orderId,
      status: status,
    );
    _startLocationTimer();
  }

  /// Принятие заказа водителем
  Future<void> acceptOrder(String orderId) async {
    if (!state.isOnline) return;

    state = state.copyWith(
      currentOrder: orderId,
      status: DriverMarkerStatus.toPickup,
    );

    _startLocationTimer();
    await _sendLocationUpdate();
  }

  /// Прибытие к клиенту (начало погрузки)
  Future<void> arrivedAtPickup() async {
    if (state.currentOrder == null) return;

    state = state.copyWith(
      status: DriverMarkerStatus.waiting,
    );

    await _sendLocationUpdate();
  }

  /// Начало движения к месту назначения (машина загружена)
  Future<void> startToDestination() async {
    if (state.currentOrder == null) return;

    state = state.copyWith(
      status: DriverMarkerStatus.toDestination,
    );

    await _sendLocationUpdate();
  }

  /// Завершение заказа
  Future<void> completeOrder() async {
    state = state.copyWith(
      clearCurrentOrder: true,
      status: DriverMarkerStatus.waiting,
    );

    _startLocationTimer();
    await _sendLocationUpdate();
  }

  /// Отправка GPS координат на сервер
  Future<void> _sendLocationUpdate() async {
    if (!mounted ||
        _sendingLocation ||
        !state.isOnline ||
        !state.isConnected ||
        state.currentLocation == null) {
      return;
    }
    _sendingLocation = true;

    try {
      final location = state.currentLocation!;
      final speed = state.speed;
      final bearing = state.bearing;

      // Отправляем на сервер
      await _realTimeService.sendDriverLocation(
        lat: location.lat,
        lng: location.lng,
        bearing: bearing,
        speed: speed,
        status: state.status,
        orderId: state.currentOrder,
        isMock: location.isMocked,
        sampledAt: state.sampledAt,
        accuracyM: state.accuracyM,
      );

      debugPrint(
        'Driver location sent: ${location.lat}, ${location.lng}, speed: ${speed.toStringAsFixed(1)} km/h',
      );
    } catch (e) {
      if (mounted) {
        state = state.copyWith(error: 'Ошибка отправки местоположения: $e');
      }
    } finally {
      _sendingLocation = false;
    }
  }

  /// Строит LocationModel из сырой GPS-позиции без обращения к геокодеру.
  LocationModel _locationFromPosition(Position position) {
    return LocationModel(
      lat: position.latitude,
      lng: position.longitude,
      address:
          '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}',
      isMocked: position.isMocked,
    );
  }

  /// Обработка входящих заказов от сервера
  void _handleOrderUpdate(OrderUpdate update) {
    if (update.status == OrderUpdateType.newOrderAssigned) {
      state = state.copyWith(
        currentOrder: update.orderId,
        status: DriverMarkerStatus.toPickup,
      );
    }
  }
}

/// Provider для real-time водителя
final driverRealTimeProvider =
    StateNotifierProvider<DriverRealTimeNotifier, DriverRealTimeState>((ref) {
  final realTimeService = ref.read(realTimeLocationServiceProvider);
  return DriverRealTimeNotifier(realTimeService);
});
