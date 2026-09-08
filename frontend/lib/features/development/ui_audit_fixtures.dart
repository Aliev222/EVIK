import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/features/auth/domain/entities/user.dart';
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'package:tow_truck_frontend/features/client/presentation/providers/order_flow_provider.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver.dart';
import 'package:tow_truck_frontend/features/map/domain/entities/map_location.dart';
import 'package:tow_truck_frontend/features/map/presentation/providers/map_provider.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order_flow_state.dart';

/// Stable, non-networked data used exclusively by the development UI audit.
/// Keep this separate from production repositories so a visual review never
/// creates an order, reads customer data, or opens a WebSocket connection.
List<Override> uiAuditOverrides() => [
      currentUserProvider.overrideWithValue(_uiAuditClient),
      mapProvider.overrideWith((ref) => _UiAuditMapNotifier()),
      orderFlowProvider.overrideWith((ref) => _UiAuditOrderFlowNotifier(ref)),
    ];

final User _uiAuditClient = User(
  id: 'ui-audit-client',
  phone: '+79991234567',
  fullName: 'Расул',
  role: UserRole.client,
  isActive: true,
  createdAt: DateTime(2026, 9, 1),
  lastSeen: DateTime(2026, 9, 4),
);

const MapLocation _pickup = MapLocation(
  latitude: 42.9849,
  longitude: 47.5047,
  address: 'проспект Расула Гамзатова, 12, Махачкала',
);

const MapLocation _destination = MapLocation(
  latitude: 42.9705,
  longitude: 47.4897,
  address: 'улица Петра I, 97, Махачкала',
);

const Driver _driver = Driver(
  userId: 'ui-audit-driver',
  fullName: 'Магомед Алиев',
  phone: '+79990001122',
  vehicleModel: 'Газель Next',
  vehicleNumber: 'А 777 АА 05',
  vehicleType: VehicleType.light,
  rating: 4.9,
  totalOrders: 286,
  isOnline: true,
  currentLocation: DriverLocation(lat: 42.9821, lng: 47.5001),
  isVerified: true,
  earnings: DriverEarnings(today: 5400, week: 24600, month: 97800),
);

final Order _order = Order(
  id: 'ui-audit-order',
  clientId: _uiAuditClient.id,
  driverId: _driver.userId,
  status: OrderStatus.onWay,
  pickupLocation: const LocationModel(
    lat: 42.9849,
    lng: 47.5047,
    address: 'проспект Расула Гамзатова, 12, Махачкала',
  ),
  dropoffLocation: const LocationModel(
    lat: 42.9705,
    lng: 47.4897,
    address: 'улица Петра I, 97, Махачкала',
  ),
  vehicleType: VehicleType.light,
  distance: 6.8,
  estimatedPrice: 1900,
  finalPrice: 1900,
  paymentMethod: PaymentMethod.card,
  createdAt: DateTime(2026, 9, 4, 14, 30),
  assignedAt: DateTime(2026, 9, 4, 14, 32),
  notes: 'Автомобиль не заводится, два заблокированных колеса',
);

class _UiAuditMapNotifier extends MapNotifier {
  @override
  Future<void> getCurrentLocation() async {
    state = state.copyWith(
      currentPosition: _pickup,
      cameraPosition: _pickup,
      permissionGranted: true,
      isLoading: false,
      error: null,
    );
  }
}

class _UiAuditOrderFlowNotifier extends OrderFlowNotifier {
  _UiAuditOrderFlowNotifier(super.ref) {
    state = OrderFlowState(
      currentStep: OrderFlowStep.vehicleSelection,
      pickupLocation: _pickup,
      destinationLocation: _destination,
      selectedVehicleType: VehicleType.light,
      selectedTowTruckType: TowTruckType.platform,
      blockedWheelsCount: 2,
      clientComment: 'Автомобиль не заводится, два заблокированных колеса',
      activeOrder: _order,
      assignedDriver: _driver,
      selectedPaymentMethod: PaymentMethod.card,
      estimatedPrice: 1900,
      distance: 6.8,
      serverPrices: const {
        TowTruckType.winch: 1600,
        TowTruckType.platform: 1900,
        TowTruckType.manipulator: 2600,
      },
    );
  }

  @override
  Future<void> restoreActiveFlow() async {}

  @override
  Future<void> detectCurrentLocation({double? lat, double? lng}) async {}
}
