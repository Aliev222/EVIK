import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroDriverColors;
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';
import 'package:tow_truck_frontend/shared/widgets/empty_state.dart';
import 'package:tow_truck_frontend/shared/widgets/error_state.dart';
import 'package:tow_truck_frontend/shared/widgets/skeleton_card.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/order_history_item.dart';
import 'package:tow_truck_frontend/features/order/presentation/providers/order_provider.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';

final driverOrderHistoryProvider =
    FutureProvider<List<OrderHistoryItem>>((ref) async {
  final repository = ref.watch(orderRepositoryProvider);

  final completedOrders = await repository.getOrdersByStatus('completed');
  final cancelledOrders = await repository.getOrdersByStatus('cancelled');

  final allOrders = <Order>[...completedOrders, ...cancelledOrders];
  allOrders.sort((a, b) => b.createdAt.compareTo(a.createdAt));

  return allOrders.map((order) => OrderHistoryItem.fromOrder(order)).toList();
});

enum DriverHistoryState { loading, empty, loaded, error }

class DriverOrdersHistoryScreen extends ConsumerStatefulWidget {
  const DriverOrdersHistoryScreen({super.key, this.onGoHome});

  final VoidCallback? onGoHome;

  @override
  ConsumerState<DriverOrdersHistoryScreen> createState() =>
      _DriverOrdersHistoryScreenState();
}

class _DriverOrdersHistoryScreenState
    extends ConsumerState<DriverOrdersHistoryScreen> {
  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(driverOrderHistoryProvider);

    return Scaffold(
      backgroundColor: AvroDriverColors.background,
      appBar: AppBar(
        title: Text(
          'История заказов',
          style: EvikTypography.h2.copyWith(fontSize: 24),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        leading: IconButton(
          onPressed: () {
            if (Navigator.of(context).canPop()) Navigator.of(context).pop();
          },
          icon: const Icon(
            Icons.arrow_back_ios,
            color: AvroDriverColors.textPrimary,
            size: 20,
          ),
          splashRadius: 24,
          padding: const EdgeInsets.all(8),
        ),
      ),
      body: ordersAsync.when(
        loading: () => ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 100),
          itemCount: 5,
          itemBuilder: (_, __) => const SkeletonCard(height: 128),
        ),
        error: (error, _) => ErrorState(
          message: 'История заказов временно недоступна.',
          onRetry: () => ref.invalidate(driverOrderHistoryProvider),
        ),
        data: (orders) {
          if (orders.isEmpty) {
            return EmptyState(
              icon: Icons.local_shipping_outlined,
              title: 'Пока заказов нет',
              subtitle: 'Включите статус «Онлайн» чтобы получать заказы',
              buttonText: 'Перейти на главную',
              onButtonTap: widget.onGoHome,
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              return _OrderHistoryCard(order: order);
            },
          );
        },
      ),
    );
  }
}

class _OrderHistoryCard extends StatelessWidget {
  final OrderHistoryItem order;

  const _OrderHistoryCard({required this.order});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AvroDriverColors.background,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.formattedDate,
                    style: EvikTypography.bodySmall.copyWith(
                      color: AvroDriverColors.grayHint,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    order.vehicleModel,
                    style: EvikTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (order.status == OrderHistoryStatus.completed) ...[
                    Text(
                      '${order.earnings} ?',
                      style: EvikTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AvroDriverColors.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Завершён',
                        style: EvikTypography.bodySmall.copyWith(
                          color: AvroDriverColors.success,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ] else ...[
                    Text(
                      '?',
                      style: EvikTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AvroDriverColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Отменён',
                        style: EvikTypography.bodySmall.copyWith(
                          color: AvroDriverColors.error,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Адреса
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AvroDriverColors.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  order.pickupAddress,
                  style: EvikTypography.bodyMedium.copyWith(
                    fontSize: 13,
                    color: AvroDriverColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AvroDriverColors.grayHint,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  order.dropoffAddress,
                  style: EvikTypography.bodyMedium.copyWith(
                    fontSize: 13,
                    color: AvroDriverColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),

          if (order.status == OrderHistoryStatus.completed) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.access_time_rounded,
                  size: 14,
                  color: AvroDriverColors.grayHint,
                ),
                const SizedBox(width: 4),
                Text(
                  '${order.duration} мин',
                  style: EvikTypography.bodySmall.copyWith(
                    color: AvroDriverColors.grayHint,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  '+${order.earnings} ?',
                  style: EvikTypography.bodySmall.copyWith(
                    color: AvroDriverColors.success,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
