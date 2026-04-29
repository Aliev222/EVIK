import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/order_flow_provider.dart';
import '../widgets/location_picker_body.dart';

class PickupLocationScreen extends ConsumerWidget {
  const PickupLocationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(orderFlowProvider);

    return LocationPickerBody(
      title: 'Откуда забрать авто?',
      addressLabel: 'Адрес подачи',
      initialLocation: state.pickupLocation,
      initialAddress: 'Выберите точку подачи',
      confirmText: 'Подтвердить адрес',
      onLocationConfirmed: (location) {
        ref.read(orderFlowProvider.notifier).setPickupLocation(location);
        ref.read(orderFlowProvider.notifier).goToDestinationSelection();
        context.push('/order/destination');
      },
    );
  }
}
