import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'package:tow_truck_frontend/core/services/realtime_location_service.dart';
import 'package:tow_truck_frontend/core/services/location_service.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/features/map/presentation/widgets/animated_driver_marker.dart';

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
    this.error,
  });

  final bool isOnline;
  final bool isConnected;
  final LocationModel? currentLocation;
  final String? currentOrder;
  final DriverMarkerStatus status;
  final double speed;
  final double bearing;
  final String? error;

  DriverRealTimeState copyWith({
    bool? isOnline,
    bool? isConnected,
    LocationModel? currentLocation,
    String? currentOrder,
    DriverMarkerStatus? status,
    double? speed,
    double? bearing,
    String? error,
  }) {
    return DriverRealTimeState(
      isOnline: isOnline ?? this.isOnline,
      isConnected: isConnected ?? this.isConnected,
      currentLocation: currentLocation ?? this.currentLocation,
      currentOrder: currentOrder ?? this.currentOrder,
      status: status ?? this.status,
      speed: speed ?? this.speed,
      bearing: bearing ?? this.bearing,
      error: error ?? this.error,
    );
  }
}

/// Real-time провайдер для водителя (отправка GPS координат)
class DriverRealTimeNotifier extends StateNotifier<DriverRealTimeState> {
  DriverRealTimeNotifier(this._realTimeService)
      : super(const DriverRealTimeState()) {
    _initializeServices();
  }

  final RealTimeLocationService _realTimeService;

  Timer? _locationTimer;
  StreamSubscription<String>? _connectionSubscription;
  StreamSubscription? _orderUpdateSubscription;
  String? _driverId;

  @override
  void dispose() {
    _locationTimer?.cancel();
    _connectionSubscription?.cancel();
    _orderUpdateSubscription?.cancel();
    _realTimeService.dispose();
    super.dispose();
  }

  void _initializeServices() {
    // Слушаем обновления заказов
    _orderUpdateSubscription = _realTimeService.orderUpdateStream.listen(
      _handleOrderUpdate,
    );
    // Слушаем статус соединения для авто-обновления isConnected после реконнекта
    _connectionSubscription = _realTimeService.connectionStream.listen((status) {
      if (status == 'connected') {
        state = state.copyWith(isConnected: true);
      } else if (status == 'disconnected' || status == 'connection_failed') {
        state = state.copyWith(isConnected: false);
      }
    });
  }

  /// Подключение водителя к real-time системе
  Future<bool> connectAsDriver(String driverId, {required String accessToken}) async {
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

    // Проверяем разрешение на геолокацию
    final hasPermission = await _checkLocationPermission();
    if (!hasPermission) {
      state = state.copyWith(error: 'Нет доступа к геолокации');
      return;
    }

    // Получаем текущее местоположение (сырые GPS-координаты без reverse-geocode)
    try {
      final position = await LocationService.getCurrentPositionWithFallback();
      final location = _locationFromPosition(position);
      state = state.copyWith(
        isOnline: true,
        currentLocation: location,
        status: DriverMarkerStatus.waiting,
        error: null,
      );
    } catch (_) {
      state = state.copyWith(error: 'Не удалось определить местоположение');
      return;
    }

    // Отправляем начальную позицию
    await _sendLocationUpdate();

    // Начинаем отправлять GPS координаты каждые 5 секунд
    _locationTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _sendLocationUpdate(),
    );
  }

  /// Завершение смены водителя (статус оффлайн)
  Future<void> goOffline() async {
    _locationTimer?.cancel();

    state = state.copyWith(
      isOnline: false,
      status: DriverMarkerStatus.waiting,
    );

    // Отправляем последнее обновление со статусом offline
    if (state.currentLocation != null) {
      await _realTimeService.sendDriverLocation(
        lat: state.currentLocation!.lat,
        lng: state.currentLocation!.lng,
        bearing: state.bearing,
        speed: state.speed,
        status: DriverMarkerStatus.waiting,
        orderId: state.currentOrder,
      );
    }

    await _realTimeService.disconnect();

    state = state.copyWith(isConnected: false);
  }

  /// Восстановление заказа после перезапуска приложения
  void restoreOrder(String orderId, DriverMarkerStatus status) {
    state = state.copyWith(
      currentOrder: orderId,
      status: status,
    );
  }

  /// Принятие заказа водителем
  Future<void> acceptOrder(String orderId) async {
    if (!state.isOnline) return;

    state = state.copyWith(
      currentOrder: orderId,
      status: DriverMarkerStatus.toPickup,
    );

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
      currentOrder: null,
      status: DriverMarkerStatus.waiting,
    );

    await _sendLocationUpdate();
  }

  /// Отправка GPS координат на сервер
  Future<void> _sendLocationUpdate() async {
    if (!state.isOnline ||
        !state.isConnected ||
        state.currentLocation == null) {
      return;
    }

    try {
      // Получаем обновленное местоположение. Используем сырые GPS-координаты
      // (getCurrentPositionWithFallback) вместо getCurrentLocation, чтобы не
      // ходить на backend за reverse-geocode на каждом 5-секундном тике.
      final position = await LocationService.getCurrentPositionWithFallback();
      final location = _locationFromPosition(position);

      // Вычисляем скорость и направление
      double speed = 0.0;
      double bearing = state.bearing;

      if (state.currentLocation != null) {
        // Простой расчет скорости (в реальном приложении используй более точные методы)
        final distance = _calculateDistance(
          state.currentLocation!.lat,
          state.currentLocation!.lng,
          location.lat,
          location.lng,
        );
        speed = distance *
            720; // Приблизительная скорость (distance за 5 сек * 720 = км/ч)

        // Простой расчет направления
        bearing = _calculateBearing(
          state.currentLocation!.lat,
          state.currentLocation!.lng,
          location.lat,
          location.lng,
        );
      }

      // Обновляем состояние
      state = state.copyWith(
        currentLocation: location,
        speed: speed,
        bearing: bearing,
        error: null,
      );

      // Отправляем на сервер
      await _realTimeService.sendDriverLocation(
        lat: location.lat,
        lng: location.lng,
        bearing: bearing,
        speed: speed,
        status: state.status,
        orderId: state.currentOrder,
        isMock: location.isMocked,
      );

      debugPrint(
        'Driver location sent: ${location.lat}, ${location.lng}, speed: ${speed.toStringAsFixed(1)} km/h',
      );
    } catch (e) {
      state = state.copyWith(error: 'Ошибка отправки местоположения: $e');
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

  /// Проверка разрешений геолокации
  Future<bool> _checkLocationPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return permission != LocationPermission.denied &&
        permission != LocationPermission.deniedForever;
  }

  /// Обработка входящих заказов от сервера
  void _handleOrderUpdate(OrderUpdate update) {
    if (update.status == OrderUpdateType.newOrderAssigned ||
        update.status == OrderUpdateType.offerAssigned) {
      state = state.copyWith(
        currentOrder: update.orderId,
        status: DriverMarkerStatus.toPickup,
      );
    }
  }

  /// Расчет расстояния между точками в км
  double _calculateDistance(
      double lat1, double lng1, double lat2, double lng2) {
    return Geolocator.distanceBetween(lat1, lng1, lat2, lng2) / 1000;
  }

  /// Расчет направления в градусах
  double _calculateBearing(double lat1, double lng1, double lat2, double lng2) {
    return Geolocator.bearingBetween(lat1, lng1, lat2, lng2);
  }
}

/// Provider для real-time водителя
final driverRealTimeProvider =
    StateNotifierProvider<DriverRealTimeNotifier, DriverRealTimeState>((ref) {
  final realTimeService = ref.read(realTimeLocationServiceProvider);
  return DriverRealTimeNotifier(realTimeService);
});
