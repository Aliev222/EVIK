import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroDriverColors;
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';
import 'package:tow_truck_frontend/shared/widgets/empty_state.dart';
import 'package:tow_truck_frontend/shared/widgets/error_state.dart';
import 'package:tow_truck_frontend/shared/widgets/skeleton_card.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/order_history_item.dart';

// Пример истории заказов
final driverOrderHistoryProvider = Provider<List<OrderHistoryItem>>((ref) {
  return [
    OrderHistoryItem(
      id: '1',
      date: DateTime.parse('2024-04-24 09:10'),
      vehicleModel: 'Toyota Camry',
      pickupAddress: 'Ленинский пр. 4',
      dropoffAddress: 'СТО Мотор, Вавилова',
      duration: 42,
      earnings: 2300,
      status: OrderHistoryStatus.completed,
    ),
    OrderHistoryItem(
      id: '2',
      date: DateTime.parse('2024-04-23 17:44'),
      vehicleModel: 'Porsche Cayenne',
      pickupAddress: 'ул. Арбат, 22',
      dropoffAddress: 'Дилерский центр, Варшавка',
      duration: 58,
      earnings: 3800,
      status: OrderHistoryStatus.completed,
    ),
    OrderHistoryItem(
      id: '3',
      date: DateTime.parse('2024-04-23 15:30'),
      vehicleModel: 'Mercedes GLE',
      pickupAddress: 'Рублёвское ш. 14',
      dropoffAddress: 'Парковка ТЦ Крокус',
      duration: 0,
      earnings: 0,
      status: OrderHistoryStatus.cancelled,
    ),
    OrderHistoryItem(
      id: '4',
      date: DateTime.parse('2024-04-22 11:00'),
      vehicleModel: 'Lada Granta',
      pickupAddress: 'ул. Большая Дмитровка',
      dropoffAddress: 'Кузовной цех №1',
      duration: 35,
      earnings: 1900,
      status: OrderHistoryStatus.completed,
    ),
  ];
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
  DriverHistoryState _state = DriverHistoryState.loaded;

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(driverOrderHistoryProvider);

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
        actions: [
          _DriverHistoryStateAction(
            label: 'Empty',
            onTap: () => setState(() => _state = DriverHistoryState.empty),
          ),
          _DriverHistoryStateAction(
            label: 'Loading',
            onTap: () => setState(() => _state = DriverHistoryState.loading),
          ),
          _DriverHistoryStateAction(
            label: 'Error',
            onTap: () => setState(() => _state = DriverHistoryState.error),
          ),
          _DriverHistoryStateAction(
            label: 'Loaded',
            onTap: () => setState(() => _state = DriverHistoryState.loaded),
          ),
        ],
      ),
      body: _buildBody(orders),
    );
  }

  Widget _buildBody(List<OrderHistoryItem> orders) {
    switch (_state) {
      case DriverHistoryState.loading:
        return ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 100),
          itemCount: 5,
          itemBuilder: (_, __) => const SkeletonCard(height: 128),
        );
      case DriverHistoryState.empty:
        return EmptyState(
          icon: Icons.local_shipping_outlined,
          title: 'Пока заказов нет',
          subtitle: 'Включите статус «Онлайн» чтобы получать заказы',
          buttonText: 'Перейти на главную',
          onButtonTap: widget.onGoHome,
        );
      case DriverHistoryState.error:
        return ErrorState(
          message: 'История заказов временно недоступна.',
          onRetry: () => setState(() => _state = DriverHistoryState.loading),
        );
      case DriverHistoryState.loaded:
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          itemCount: orders.length,
          itemBuilder: (context, index) {
            final order = orders[index];
            return _OrderHistoryCard(order: order);
          },
        );
    }
  }
}

class _DriverHistoryStateAction extends StatelessWidget {
  const _DriverHistoryStateAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      child: Text(
        label,
        style: EvikTypography.bodySmall.copyWith(
          color: AvroDriverColors.accent,
          fontWeight: FontWeight.w800,
        ),
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
