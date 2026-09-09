import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tow_truck_frontend/core/services/realtime_location_service.dart';
import 'package:tow_truck_frontend/features/driver/data/services/driver_location_service.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/driver_realtime_provider.dart';
import 'package:tow_truck_frontend/features/map/presentation/widgets/animated_driver_marker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('online uses background stream, preserves restored trip and clears ended order', () async {
    final transport = _Transport();
    final location = _Location();
    final notifier = DriverRealTimeNotifier(transport, locationService: location);
    addTearDown(notifier.dispose);
    addTearDown(transport.dispose);
    await notifier.connectAsDriver('driver', accessToken: 'token');
    notifier.restoreOrder('trip', DriverMarkerStatus.toDestination);
    await notifier.goOnline();
    expect(location.requiredBackground, isTrue);
    expect(location.tracking, isTrue);
    expect(notifier.state.status, DriverMarkerStatus.toDestination);

    location.emit(speed: 10, heading: 90);
    await Future<void>.delayed(Duration.zero);
    expect(transport.lastSpeed, 36);
    expect(transport.lastOrderId, 'trip');
    await notifier.completeOrder();
    expect(notifier.state.currentOrder, isNull);
    expect(transport.lastOrderId, isNull);
    await notifier.goOffline();
    expect(location.tracking, isFalse);
    expect(notifier.state.isOnline, isFalse);
  });

  test('an offer is not an accepted order', () async {
    final transport = _Transport();
    final notifier = DriverRealTimeNotifier(transport, locationService: _Location());
    addTearDown(notifier.dispose);
    addTearDown(transport.dispose);
    transport.orders.add(OrderUpdate(orderId: 'offered', status: OrderUpdateType.offerAssigned));
    await Future<void>.delayed(Duration.zero);
    expect(notifier.state.currentOrder, isNull);
  });

  test('denied background permission does not enter online state', () async {
    final transport = _Transport();
    final location = _Location()..denyPermission = true;
    final notifier = DriverRealTimeNotifier(transport, locationService: location);
    addTearDown(notifier.dispose);
    addTearDown(transport.dispose);
    await notifier.connectAsDriver('driver', accessToken: 'token');
    await notifier.goOnline();
    expect(notifier.state.isOnline, isFalse);
    expect(location.tracking, isFalse);
    expect(notifier.state.error, contains('permission denied'));
  });
}

class _Location extends DriverLocationService {
  bool tracking = false;
  bool requiredBackground = false;
  bool denyPermission = false;
  void Function(Position)? onPosition;

  Position position({double speed = 0, double heading = 0}) => Position(
    longitude: 47.5, latitude: 42.98, timestamp: DateTime.now(), accuracy: 5,
    altitude: 0, altitudeAccuracy: 0, heading: heading, headingAccuracy: 0,
    speed: speed, speedAccuracy: 0,
  );

  void emit({required double speed, required double heading}) => onPosition?.call(position(speed: speed, heading: heading));

  @override
  Future<bool> checkPermissions({bool requireBackground = false}) async {
    requiredBackground = requireBackground;
    if (denyPermission) throw const DriverLocationException('permission denied');
    return true;
  }

  @override
  Future<Position> getCurrentPosition() async => position();

  @override
  Future<void> startLocationTracking({required String driverId, Duration interval = const Duration(seconds: 10), void Function(Position)? onPosition, void Function(Object)? onError}) async {
    tracking = true;
    this.onPosition = onPosition;
  }

  @override
  Future<void> stopLocationTracking() async { tracking = false; }
}

class _Transport extends RealTimeLocationService {
  final orders = StreamController<OrderUpdate>.broadcast();
  final connections = StreamController<String>.broadcast();
  String? lastOrderId;
  double? lastSpeed;

  @override
  Stream<OrderUpdate> get orderUpdateStream => orders.stream;
  @override
  Stream<String> get connectionStream => connections.stream;
  @override
  Future<bool> connect({
    required String userId,
    required String userType,
    String accessToken = '',
  }) async => true;
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> sendDriverLocation({required double lat, required double lng, double bearing = 0, double speed = 0, DriverMarkerStatus status = DriverMarkerStatus.waiting, String? orderId, bool isMock = false}) async {
    lastOrderId = orderId;
    lastSpeed = speed;
  }
  @override
  void dispose() {
    orders.close();
    connections.close();
  }
}
