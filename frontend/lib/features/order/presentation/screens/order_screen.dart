import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/widgets/app_scaffold.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/features/order/domain/repositories/order_repository.dart';
import 'package:tow_truck_frontend/features/order/presentation/state/order_state_notifier.dart';
import '../widgets/order_state_views.dart';

class OrderScreen extends ConsumerWidget {
  const OrderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiState = ref.watch(orderStateNotifierProvider);

    final body = switch (uiState.status) {
      OrderState.idle => IdleOrderView(
          onCreate: () {
            ref.read(orderStateNotifierProvider.notifier).submitOrder(
                  const CreateOrderCommand(
                    userId: 'demo-user',
                    pickup: Coordinate(lat: 55.751244, lng: 37.618423),
                    dropoff: Coordinate(lat: 55.761244, lng: 37.628423),
                  ),
                );
          },
        ),
      OrderState.searching => const SearchingOrderView(),
      OrderState.accepted => const AcceptedOrderView(),
      OrderState.arrived => const ArrivedOrderView(),
      OrderState.inProgress => const InProgressOrderView(),
      OrderState.completed => const CompletedOrderView(),
      OrderState.cancelled => const CancelledOrderView(),
      OrderState.noDriverFound => NoDriverFoundOrderView(
          onRetry: () {
            ref.read(orderStateNotifierProvider.notifier).submitOrder(
                  const CreateOrderCommand(
                    userId: 'demo-user',
                    pickup: Coordinate(lat: 55.751244, lng: 37.618423),
                    dropoff: Coordinate(lat: 55.761244, lng: 37.628423),
                  ),
                );
          },
        ),
    };

    return AppScaffold(child: body);
  }
}
