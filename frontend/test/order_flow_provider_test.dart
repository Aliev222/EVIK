import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tow_truck_frontend/features/client/presentation/providers/order_flow_provider.dart';
import 'package:tow_truck_frontend/features/map/domain/entities/map_location.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order_flow_state.dart';

void main() {
  test('order flow stores route and recalculates estimated price', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(orderFlowProvider.notifier);

    notifier.startOrderFlow();
    notifier.setPickupLocation(
      const MapLocation(
        latitude: 55.7558,
        longitude: 37.6173,
        address: 'Москва, центр',
      ),
    );
    notifier.goToDestinationSelection();
    notifier.setDestinationLocation(
      const MapLocation(
        latitude: 55.7812,
        longitude: 37.6095,
        address: 'Проспект Мира',
      ),
    );
    notifier.goToVehicleSelection();
    notifier.selectVehicleType(VehicleType.suv);
    notifier.selectTowTruckType(TowTruckType.platform);

    final state = container.read(orderFlowProvider);
    expect(state.currentStep, OrderFlowStep.vehicleSelection);
    expect(state.pickupLocation?.displayAddress, 'Москва, центр');
    expect(state.destinationLocation?.displayAddress, 'Проспект Мира');
    expect(state.distance, greaterThan(0));
    expect(state.estimatedPrice, greaterThan(1800));
  });
}
