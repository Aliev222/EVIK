import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/features/map/presentation/widgets/animated_driver_marker.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';

/// Real-time сервис для WebSocket связи и отслеживания местоположения
class RealTimeLocationService {
  static const String _wsUrl = String.fromEnvironment(
    'EVIK_LOCATION_WS_URL',
    defaultValue: 'wss://tow-truck.onrender.com/ws/orders',
  );

  WebSocketChannel? _channel;
  bool _isConnected = false;
  String? _savedUserId;
  String? _savedUserType;
  String? _userId;
  String? _userType;
  String? _savedAccessToken;
  bool _shouldReconnect = false;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  int _connectionGeneration = 0;
  int _reconnectAttempts = 0;
  final Map<String, DriverLocationUpdate> _lastDriverUpdateByOrder = {};

  // Stream controllers для потоков данных локации
  final StreamController<DriverLocationUpdate> _driverLocationController =
      StreamController<DriverLocationUpdate>.broadcast();
  final StreamController<OrderUpdate> _orderUpdateController =
      StreamController<OrderUpdate>.broadcast();
  final StreamController<ClientLocationUpdate> _clientLocationController =
      StreamController<ClientLocationUpdate>.broadcast();
  final StreamController<String> _connectionController =
      StreamController<String>.broadcast();

  // Getters для доступа
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
    String accessToken = '',
  }) async {
    try {
      final sameIdentity = _userId == userId &&
          _userType == userType &&
          _savedAccessToken == accessToken;
      if (_isConnected && sameIdentity) return true;
      if (_isConnected || _channel != null) {
        final oldChannel = _channel;
        _channel = null;
        _isConnected = false;
        await oldChannel?.sink.close();
      }
      _savedUserId = userId;
      _savedUserType = userType;
      _userId = userId;
      _userType = userType;
      _savedAccessToken = accessToken;
      _shouldReconnect = true;
      _reconnectTimer?.cancel();

      final generation = ++_connectionGeneration;

      var wsUrl = _wsUrl;
      if (accessToken.isNotEmpty) {
        wsUrl = Uri.parse(_wsUrl).replace(
          queryParameters: <String, String>{'access_token': accessToken},
        ).toString();
      }
      final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _channel = channel;
      await channel.ready;

      if (generation != _connectionGeneration) return false;

      // Слушаем входящие сообщения
      channel.stream.listen(
        (message) {
          if (generation == _connectionGeneration) _handleMessage(message);
        },
        onError: (Object error, StackTrace stackTrace) {
          if (generation == _connectionGeneration) _handleError(error);
        },
        onDone: () {
          if (generation == _connectionGeneration) _handleDisconnection();
        },
      );

      // Переподключаемся к серверу
      await _register();

      _isConnected = true;
      _reconnectAttempts = 0;
      _connectionController.add('connected');
      _startPingTimer();

      debugPrint('WebSocket connected as $_userType: $_userId');
      return true;
    } catch (e) {
      debugPrint('WebSocket connection failed: $e');
      _isConnected = false;
      _connectionController.add('connection_failed');
      if (_shouldReconnect && _savedUserId != null && _savedUserType != null) {
        _scheduleReconnect();
      }
      return false;
    }
  }

  /// Отправляем идентификацию на сервер
  Future<void> _register() async {
    final message = {
      'type': 'register_$_userType',
      '${_userType}_id': _userId,
      'timestamp': DateTime.now().toIso8601String(),
    };

    _sendMessage(message);
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_isConnected) {
        _sendMessage({'type': 'ping'});
      }
    });
  }

  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  void _scheduleReconnect() {
    if (_reconnectTimer?.isActive == true) return;
    final exponent = _reconnectAttempts.clamp(0, 4);
    _reconnectAttempts += 1;
    final jitterMs = DateTime.now().microsecond % 700;
    final delay = Duration(seconds: 1 << exponent, milliseconds: jitterMs);
    _reconnectTimer = Timer(delay, () async {
      _reconnectTimer = null;
      if (_savedUserId != null && _savedUserType != null && _shouldReconnect) {
        await connect(
          userId: _savedUserId!,
          userType: _savedUserType!,
          accessToken: _savedAccessToken ?? '',
        );
      }
    });
  }

  /// Отправка GPS координат водителя на сервер
  Future<void> sendDriverLocation({
    required double lat,
    required double lng,
    required double bearing,
    required double speed,
    required DriverMarkerStatus status,
    String? orderId,
    bool isMock = false,
    DateTime? sampledAt,
    double? accuracyM,
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
        'speed_kmh': speed,
        'speed_mps': speed / 3.6,
        if (accuracyM != null) 'accuracy_m': accuracyM,
        'status': _wireDriverStatus(status),
        'order_id': orderId,
        'is_mock': isMock,
        'sampled_at': (sampledAt ?? DateTime.now()).toUtc().toIso8601String(),
      },
      'timestamp': DateTime.now().toIso8601String(),
    };

    _sendMessage(message);
  }

  Future<void> sendClientLocation({
    required double lat,
    required double lng,
    String? orderId,
    bool isMock = false,
  }) async {
    if (!_isConnected || _userType != 'client') return;

    final message = {
      'type': 'client_location_update',
      'client_id': _userId,
      'data': {
        'lat': lat,
        'lng': lng,
        'order_id': orderId,
        'is_mock': isMock,
      },
      'timestamp': DateTime.now().toIso8601String(),
    };

    _sendMessage(message);
  }

  /// Отправка заказа водителю
  Future<void> createOrder({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    required VehicleType vehicleType,
    String? notes,
    bool isMock = false,
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
        'is_mock': isMock,
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

        case 'driver_location':
          _handleServerDriverLocation(message);
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

        case 'offer':
        case 'order_offer':
          _handleOffer(message);
          break;

        case 'ping':
        case 'pong':
          break;

        case 'initial_state':
          _handleInitialState(message);
          break;

        case 'payment_method_changed':
          _handlePaymentMethodChanged(message);
          break;

        case 'order_route_changed':
          final orderId = message['order_id']?.toString() ?? '';
          if (orderId.isNotEmpty) {
            _orderUpdateController.add(OrderUpdate(
                orderId: orderId, status: OrderUpdateType.routeChanged));
          }
          break;

        case 'cancelled':
          _handleOrderCancelled(message);
          break;

        case 'completed':
          _orderUpdateController.add(OrderUpdate(
            orderId: message['order_id']?.toString() ?? '',
            status: OrderUpdateType.orderCompleted,
            rawPayload: message['payload'] is Map<String, dynamic>
                ? message['payload'] as Map<String, dynamic>
                : null,
          ));
          break;

        default:
          debugPrint('Received unknown message type: $type');
      }
    } catch (e) {
      debugPrint('Error handling message: $e');
    }
  }

  /// Обработка обновления местоположения водителя (формат сервера)
  void _handleServerDriverLocation(Map<String, dynamic> message) {
    try {
      final payload = message['payload'] as Map<String, dynamic>?;
      if (payload == null) return;
      final orderId = message['order_id']?.toString();
      final previous =
          orderId == null ? null : _lastDriverUpdateByOrder[orderId];
      final sequence = (payload['seq'] as num?)?.toInt();
      final sampledAt = _parseMeasurementTime(payload['sampled_at'] ??
          payload['timestamp'] ??
          message['timestamp']);
      final receivedAt = _parseOptionalTime(payload['received_at']);
      if (previous != null) {
        final timeOrder = sampledAt.compareTo(previous.timestamp);
        // WS and HTTP publishers may use independent sequence counters. Time
        // is therefore the primary cross-transport watermark; seq only breaks
        // ties for two events representing the same device sample.
        if (timeOrder < 0 ||
            (timeOrder == 0 &&
                (sequence == null ||
                    previous.sequence == null ||
                    sequence <= previous.sequence!))) {
          return;
        }
      }
      final update = DriverLocationUpdate(
        driverId: payload['driver_id']?.toString() ?? '',
        lat: (payload['lat'] as num?)?.toDouble() ?? 0.0,
        lng: (payload['lng'] as num?)?.toDouble() ?? 0.0,
        // HTTP heartbeats may omit optional motion fields.  Missing is not
        // zero: retain the last confirmed direction/speed instead of turning
        // the marker north or reverting the phase.
        bearing: (payload['bearing'] as num?)?.toDouble() ??
            previous?.bearing ??
            0.0,
        speed: (payload['speed'] as num?)?.toDouble() ?? previous?.speed ?? 0.0,
        status: payload['status'] == null
            ? previous?.status ?? DriverMarkerStatus.toPickup
            : _parseDriverStatus(payload['status']?.toString()),
        orderId: orderId,
        timestamp: sampledAt,
        sequence: sequence,
        receivedAt: receivedAt,
        accuracyM: (payload['accuracy_m'] as num?)?.toDouble(),
      );
      if (orderId != null && orderId.isNotEmpty) {
        _lastDriverUpdateByOrder[orderId] = update;
      }
      _driverLocationController.add(update);
    } catch (e) {
      debugPrint('Error parsing server driver location: $e');
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
      final orderId = update.orderId;
      final previous =
          orderId == null ? null : _lastDriverUpdateByOrder[orderId];
      if (previous != null && !update.timestamp.isAfter(previous.timestamp)) {
        return;
      }
      if (orderId != null && orderId.isNotEmpty) {
        _lastDriverUpdateByOrder[orderId] = update;
      }
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

  /// Обработка обновления статуса для клиента
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

  /// Обработка обновления заказа новым водителем
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

  /// Обработка отсутствия свободных водителей
  void _handleNoDriversAvailable(Map<String, dynamic> message) {
    final orderUpdate = OrderUpdate(
      orderId: message['order_id'],
      status: OrderUpdateType.noDriversAvailable,
      message: message['message'],
    );

    _orderUpdateController.add(orderUpdate);
  }

  /// Обработка оффера (входящий заказ для водителя)
  void _handleOffer(Map<String, dynamic> message) {
    try {
      final orderId = message['order_id']?.toString() ?? '';
      final orderData = message['payload'] ?? message;
      final orderUpdate = OrderUpdate(
        orderId: orderId,
        status: OrderUpdateType.offerAssigned,
        message: message['message'],
        pickupLat: orderData['pickup_lat']?.toDouble(),
        pickupLng: orderData['pickup_lng']?.toDouble(),
        dropoffLat: orderData['dropoff_lat']?.toDouble(),
        dropoffLng: orderData['dropoff_lng']?.toDouble(),
        clientId: orderData['client_id'],
        rawPayload: orderData is Map<String, dynamic> ? orderData : null,
      );
      _orderUpdateController.add(orderUpdate);
    } catch (e) {
      debugPrint('Error parsing offer: $e');
    }
  }

  /// Обработка начального состояния для карты клиента
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

  /// Обработка смены метода оплаты (в т.ч. во время поездки)
  void _handlePaymentMethodChanged(Map<String, dynamic> message) {
    try {
      final orderId = message['order_id']?.toString() ?? '';
      if (orderId.isEmpty) return;
      _orderUpdateController.add(
        OrderUpdate(
          orderId: orderId,
          status: OrderUpdateType.paymentMethodChanged,
          rawPayload: message['payload'] is Map<String, dynamic>
              ? message['payload'] as Map<String, dynamic>
              : null,
        ),
      );
    } catch (e) {
      debugPrint('Error parsing payment_method_changed: $e');
    }
  }

  /// Обработка отмены заказа
  void _handleOrderCancelled(Map<String, dynamic> message) {
    try {
      final orderId = message['order_id']?.toString() ?? '';
      if (orderId.isEmpty) return;
      _orderUpdateController.add(
        OrderUpdate(
          orderId: orderId,
          status: OrderUpdateType.orderCancelled,
          rawPayload: message['payload'] is Map<String, dynamic>
              ? message['payload'] as Map<String, dynamic>
              : null,
        ),
      );
    } catch (e) {
      debugPrint('Error parsing cancelled: $e');
    }
  }

  /// Парсинг статуса водителя
  DriverMarkerStatus _parseDriverStatus(String? status) {
    final normalized = (status ?? '')
        .replaceAll('toDestination', 'to_destination')
        .replaceAll('toPickup', 'to_pickup')
        .toLowerCase();
    switch (normalized) {
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

  String _wireDriverStatus(DriverMarkerStatus status) {
    return switch (status) {
      DriverMarkerStatus.toPickup => 'to_pickup',
      DriverMarkerStatus.toDestination => 'to_destination',
      DriverMarkerStatus.waiting => 'waiting',
    };
  }

  DateTime _parseMeasurementTime(Object? value) {
    return DateTime.tryParse(value?.toString() ?? '')?.toLocal() ??
        DateTime.now();
  }

  DateTime? _parseOptionalTime(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '')?.toLocal();

  /// Отправка сообщения на сервер
  void _sendMessage(Map<String, dynamic> message) {
    if (_isConnected && _channel != null) {
      _channel!.sink.add(json.encode(message));
    }
  }

  /// Обработка ошибок WebSocket
  void _handleError(Object error) {
    debugPrint('WebSocket error: $error');
    _stopPingTimer();
    _isConnected = false;
    _connectionController.add('error');
    if (_shouldReconnect) {
      _scheduleReconnect();
    }
  }

  /// Обработка отключения WebSocket
  void _handleDisconnection() {
    debugPrint('WebSocket disconnected');
    _stopPingTimer();
    _isConnected = false;
    _connectionController.add('disconnected');
    if (_shouldReconnect) {
      _scheduleReconnect();
    }
  }

  /// Отключение от сервера
  Future<void> disconnect() async {
    _shouldReconnect = false;
    _connectionGeneration += 1;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopPingTimer();
    _isConnected = false;
    await _channel?.sink.close();
    _channel = null;
    _lastDriverUpdateByOrder.clear();
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

/// Класс для обновления местоположения водителя
class DriverLocationUpdate {
  final String driverId;
  final double lat;
  final double lng;
  final double bearing;
  final double speed;
  final DriverMarkerStatus status;
  final String? orderId;
  final DateTime timestamp;
  final int? sequence;
  final DateTime? receivedAt;
  final double? accuracyM;

  const DriverLocationUpdate({
    required this.driverId,
    required this.lat,
    required this.lng,
    required this.bearing,
    required this.speed,
    required this.status,
    this.orderId,
    required this.timestamp,
    this.sequence,
    this.receivedAt,
    this.accuracyM,
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

/// Класс для обновления заказа
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
  final Map<String, dynamic>? rawPayload;

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
    this.rawPayload,
  });
}

/// Тип обновления заказа
enum OrderUpdateType {
  driverFound,
  newOrderAssigned,
  noDriversAvailable,
  orderCompleted,
  offerAssigned,
  paymentMethodChanged,
  routeChanged,
  orderCancelled,
}

/// Provider для real-time сервиса
final realTimeLocationServiceProvider =
    Provider<RealTimeLocationService>((ref) {
  return RealTimeLocationService();
});
