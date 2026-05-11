import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/order/domain/entities/order.dart';
import '../../../features/map/presentation/widgets/animated_driver_marker.dart';

/// Real-time сервис для WebSocket связи с сервером местоположений
class RealTimeLocationService {
  static const String _wsUrl = String.fromEnvironment(
    'EVIK_LOCATION_WS_URL',
    defaultValue: 'wss://tow-truck.onrender.com/ws/orders',
  );

  WebSocketChannel? _channel;
  bool _isConnected = false;
  String? _userId;
  String? _userType; // 'driver', 'client', 'admin'

  // Stream controllers для разных типов данных
  final StreamController<DriverLocationUpdate> _driverLocationController =
      StreamController<DriverLocationUpdate>.broadcast();
  final StreamController<OrderUpdate> _orderUpdateController =
      StreamController<OrderUpdate>.broadcast();
  final StreamController<ClientLocationUpdate> _clientLocationController =
      StreamController<ClientLocationUpdate>.broadcast();
  final StreamController<String> _connectionController =
      StreamController<String>.broadcast();

  // Getters для стримов
  Stream<DriverLocationUpdate> get driverLocationStream =>
      _driverLocationController.stream;
  Stream<OrderUpdate> get orderUpdateStream => _orderUpdateController.stream;
  Stream<ClientLocationUpdate> get clientLocationStream =>
      _clientLocationController.stream;
  Stream<String> get connectionStream => _connectionController.stream;

  bool get isConnected => _isConnected;

  /// Подключение к WebSocket серверу
  Future<bool> connect({
    required String userId,
    required String userType, // 'driver', 'client', 'admin'
  }) async {
    try {
      _userId = userId;
      _userType = userType;

      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));

      // Слушаем входящие сообщения
      _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDisconnection,
      );

      // Регистрируемся на сервере
      await _register();

      _isConnected = true;
      _connectionController.add('connected');

      debugPrint('WebSocket connected as $_userType: $_userId');
      return true;
    } catch (e) {
      debugPrint('WebSocket connection failed: $e');
      _isConnected = false;
      _connectionController.add('connection_failed');
      return false;
    }
  }

  /// Регистрация пользователя на сервере
  Future<void> _register() async {
    final message = {
      'type': 'register_$_userType',
      '${_userType}_id': _userId,
      'timestamp': DateTime.now().toIso8601String(),
    };

    _sendMessage(message);
  }

  /// Отправка GPS координат водителя на сервер
  Future<void> sendDriverLocation({
    required double lat,
    required double lng,
    required double bearing,
    required double speed,
    required DriverMarkerStatus status,
    String? orderId,
  }) async {
    if (!_isConnected || _userType != 'driver') return;

    final message = {
      'type': 'location_update',
      'driver_id': _userId,
      'data': {
        'lat': lat,
        'lng': lng,
        'bearing': bearing,
        'speed': speed,
        'status': status.name,
        'order_id': orderId,
      },
      'timestamp': DateTime.now().toIso8601String(),
    };

    _sendMessage(message);
  }

  Future<void> sendClientLocation({
    required double lat,
    required double lng,
    String? orderId,
  }) async {
    if (!_isConnected || _userType != 'client') return;

    final message = {
      'type': 'client_location_update',
      'client_id': _userId,
      'data': {
        'lat': lat,
        'lng': lng,
        'order_id': orderId,
      },
      'timestamp': DateTime.now().toIso8601String(),
    };

    _sendMessage(message);
  }

  /// Создание заказа клиентом
  Future<void> createOrder({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    required VehicleType vehicleType,
    String? notes,
  }) async {
    if (!_isConnected || _userType != 'client') return;

    final message = {
      'type': 'create_order',
      'client_id': _userId,
      'data': {
        'pickup_lat': pickupLat,
        'pickup_lng': pickupLng,
        'dropoff_lat': dropoffLat,
        'dropoff_lng': dropoffLng,
        'vehicle_type': vehicleType.name,
        'notes': notes,
      },
      'timestamp': DateTime.now().toIso8601String(),
    };

    _sendMessage(message);
  }

  /// Обработка входящих сообщений от сервера
  void _handleMessage(dynamic rawMessage) {
    try {
      final message = json.decode(rawMessage);
      final type = message['type'];

      switch (type) {
        case 'connection_established':
          debugPrint('Connection established: ${message['message']}');
          break;

        case 'driver_location_update':
          _handleDriverLocationUpdate(message);
          break;

        case 'client.location.updated':
        case 'client_location_update':
          _handleClientLocationUpdate(message);
          break;

        case 'driver_found':
          _handleDriverFound(message);
          break;

        case 'new_order_assigned':
          _handleNewOrderAssigned(message);
          break;

        case 'no_drivers_available':
          _handleNoDriversAvailable(message);
          break;

        case 'initial_state':
          _handleInitialState(message);
          break;

        default:
          debugPrint('Received unknown message type: $type');
      }
    } catch (e) {
      debugPrint('Error handling message: $e');
    }
  }

  /// Обработка обновления местоположения водителя
  void _handleDriverLocationUpdate(Map<String, dynamic> message) {
    try {
      final location = message['location'];
      final update = DriverLocationUpdate(
        driverId: location['driver_id'],
        lat: location['lat']?.toDouble() ?? 0.0,
        lng: location['lng']?.toDouble() ?? 0.0,
        bearing: location['bearing']?.toDouble() ?? 0.0,
        speed: location['speed']?.toDouble() ?? 0.0,
        status: _parseDriverStatus(location['status']),
        orderId: location['order_id'],
        timestamp: DateTime.parse(location['last_update']),
      );

      _driverLocationController.add(update);
    } catch (e) {
      debugPrint('Error parsing driver location: $e');
    }
  }

  void _handleClientLocationUpdate(Map<String, dynamic> message) {
    try {
      final location = message['location'] ?? message['data'];
      if (location == null) return;

      _clientLocationController.add(
        ClientLocationUpdate(
          clientId: message['client_id'] ?? location['client_id'] ?? '',
          lat: location['lat']?.toDouble() ?? 0.0,
          lng: location['lng']?.toDouble() ?? 0.0,
          orderId: message['order_id'] ?? location['order_id'],
          timestamp: DateTime.tryParse(
                location['last_update']?.toString() ??
                    message['timestamp']?.toString() ??
                    '',
              ) ??
              DateTime.now(),
        ),
      );
    } catch (e) {
      debugPrint('Error parsing client location: $e');
    }
  }

  /// Обработка найденного водителя для клиента
  void _handleDriverFound(Map<String, dynamic> message) {
    try {
      final driverData = message['driver'];
      final orderUpdate = OrderUpdate(
        orderId: message['order_id'],
        status: OrderUpdateType.driverFound,
        message: message['message'],
        driver: DriverLocationUpdate(
          driverId: driverData['driver_id'],
          lat: driverData['lat']?.toDouble() ?? 0.0,
          lng: driverData['lng']?.toDouble() ?? 0.0,
          bearing: driverData['bearing']?.toDouble() ?? 0.0,
          speed: driverData['speed']?.toDouble() ?? 0.0,
          status: _parseDriverStatus(driverData['status']),
          orderId: driverData['order_id'],
          timestamp: DateTime.parse(driverData['last_update']),
        ),
      );

      _orderUpdateController.add(orderUpdate);
    } catch (e) {
      debugPrint('Error parsing driver found: $e');
    }
  }

  /// Обработка назначения нового заказа водителю
  void _handleNewOrderAssigned(Map<String, dynamic> message) {
    try {
      final orderData = message['order'];
      final orderUpdate = OrderUpdate(
        orderId: orderData['order_id'],
        status: OrderUpdateType.newOrderAssigned,
        message: message['message'],
        pickupLat: orderData['pickup_lat']?.toDouble(),
        pickupLng: orderData['pickup_lng']?.toDouble(),
        dropoffLat: orderData['dropoff_lat']?.toDouble(),
        dropoffLng: orderData['dropoff_lng']?.toDouble(),
        clientId: orderData['client_id'],
      );

      _orderUpdateController.add(orderUpdate);
    } catch (e) {
      debugPrint('Error parsing new order: $e');
    }
  }

  /// Обработка отсутствия доступных водителей
  void _handleNoDriversAvailable(Map<String, dynamic> message) {
    final orderUpdate = OrderUpdate(
      orderId: message['order_id'],
      status: OrderUpdateType.noDriversAvailable,
      message: message['message'],
    );

    _orderUpdateController.add(orderUpdate);
  }

  /// Обработка начального состояния для админ панели
  void _handleInitialState(Map<String, dynamic> message) {
    try {
      final drivers = message['drivers'] as List;
      for (final driverData in drivers) {
        final update = DriverLocationUpdate(
          driverId: driverData['driver_id'],
          lat: driverData['lat']?.toDouble() ?? 0.0,
          lng: driverData['lng']?.toDouble() ?? 0.0,
          bearing: driverData['bearing']?.toDouble() ?? 0.0,
          speed: driverData['speed']?.toDouble() ?? 0.0,
          status: _parseDriverStatus(driverData['status']),
          orderId: driverData['order_id'],
          timestamp: DateTime.parse(driverData['last_update']),
        );

        _driverLocationController.add(update);
      }
    } catch (e) {
      debugPrint('Error parsing initial state: $e');
    }
  }

  /// Парсинг статуса водителя
  DriverMarkerStatus _parseDriverStatus(String? status) {
    switch (status) {
      case 'to_pickup':
        return DriverMarkerStatus.toPickup;
      case 'to_destination':
        return DriverMarkerStatus.toDestination;
      case 'waiting':
        return DriverMarkerStatus.waiting;
      default:
        return DriverMarkerStatus.toPickup;
    }
  }

  /// Отправка сообщения на сервер
  void _sendMessage(Map<String, dynamic> message) {
    if (_isConnected && _channel != null) {
      _channel!.sink.add(json.encode(message));
    }
  }

  /// Обработка ошибок WebSocket
  void _handleError(error) {
    debugPrint('WebSocket error: $error');
    _isConnected = false;
    _connectionController.add('error');
  }

  /// Обработка отключения WebSocket
  void _handleDisconnection() {
    debugPrint('WebSocket disconnected');
    _isConnected = false;
    _connectionController.add('disconnected');
  }

  /// Отключение от сервера
  Future<void> disconnect() async {
    _isConnected = false;
    await _channel?.sink.close();
    _channel = null;
    _connectionController.add('disconnected');
  }

  /// Очистка ресурсов
  void dispose() {
    disconnect();
    _driverLocationController.close();
    _orderUpdateController.close();
    _clientLocationController.close();
    _connectionController.close();
  }
}

/// Класс для обновлений местоположения водителей
class DriverLocationUpdate {
  final String driverId;
  final double lat;
  final double lng;
  final double bearing;
  final double speed;
  final DriverMarkerStatus status;
  final String? orderId;
  final DateTime timestamp;

  const DriverLocationUpdate({
    required this.driverId,
    required this.lat,
    required this.lng,
    required this.bearing,
    required this.speed,
    required this.status,
    this.orderId,
    required this.timestamp,
  });

  LocationModel get location => LocationModel(
        lat: lat,
        lng: lng,
        address: 'Driver $driverId',
      );
}

class ClientLocationUpdate {
  const ClientLocationUpdate({
    required this.clientId,
    required this.lat,
    required this.lng,
    required this.timestamp,
    this.orderId,
  });

  final String clientId;
  final double lat;
  final double lng;
  final DateTime timestamp;
  final String? orderId;

  LocationModel get location => LocationModel(
        lat: lat,
        lng: lng,
        address: 'Client $clientId',
      );
}

/// Класс для обновлений заказов
class OrderUpdate {
  final String orderId;
  final OrderUpdateType status;
  final String? message;
  final DriverLocationUpdate? driver;
  final double? pickupLat;
  final double? pickupLng;
  final double? dropoffLat;
  final double? dropoffLng;
  final String? clientId;

  const OrderUpdate({
    required this.orderId,
    required this.status,
    this.message,
    this.driver,
    this.pickupLat,
    this.pickupLng,
    this.dropoffLat,
    this.dropoffLng,
    this.clientId,
  });
}

/// Типы обновлений заказов
enum OrderUpdateType {
  driverFound,
  newOrderAssigned,
  noDriversAvailable,
  orderCompleted,
}

/// Provider для real-time сервиса
final realTimeLocationServiceProvider =
    Provider<RealTimeLocationService>((ref) {
  return RealTimeLocationService();
});
