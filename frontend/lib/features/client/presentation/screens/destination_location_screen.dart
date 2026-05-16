import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:tow_truck_frontend/features/client/presentation/providers/order_flow_provider.dart';
import 'package:tow_truck_frontend/features/client/presentation/widgets/location_picker_body.dart';

class DestinationLocationScreen extends ConsumerWidget {
  const DestinationLocationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(orderFlowProvider);

    return LocationPickerBody(
      title: 'Куда отвезти авто?',
      addressLabel: 'Адрес доставки',
      initialLocation: state.destinationLocation ?? state.pickupLocation,
      initialAddress: 'Выберите адрес доставки',
      confirmText: 'Продолжить',
      onLocationConfirmed: (location) {
        ref.read(orderFlowProvider.notifier).setDestinationLocation(location);
        ref.read(orderFlowProvider.notifier).goToVehicleSelection();
        context.push('/order/vehicle');
      },
    );
  }
}
