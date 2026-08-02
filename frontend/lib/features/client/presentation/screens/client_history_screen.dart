import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroClientColors;
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';
import 'package:tow_truck_frontend/shared/widgets/empty_state.dart';
import 'package:tow_truck_frontend/shared/widgets/error_state.dart';
import 'package:tow_truck_frontend/shared/widgets/animated_list_item.dart';
import 'package:tow_truck_frontend/shared/widgets/skeleton_card.dart';
import 'package:tow_truck_frontend/shared/widgets/evik_button.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/features/order/presentation/providers/order_provider.dart';
import 'package:tow_truck_frontend/features/review/presentation/providers/review_provider.dart';

enum HistoryState { loading, empty, loaded, error }

class ClientHistoryScreen extends ConsumerStatefulWidget {
  const ClientHistoryScreen({super.key, this.onSwitchToHome});

  final VoidCallback? onSwitchToHome;

  @override
  ConsumerState<ClientHistoryScreen> createState() => _ClientHistoryScreenState();
}

class _ClientHistoryScreenState extends ConsumerState<ClientHistoryScreen> {
  HistoryState _state = HistoryState.loading;
  List<Order> _orders = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    try {
      setState(() {
        _state = HistoryState.loading;
        _error = null;
      });

      final orderRepository = ref.read(orderRepositoryProvider);
      final orders = await orderRepository.getOrders();
      if (!mounted) return;

      setState(() {
        _orders = orders;
        _state = orders.isEmpty ? HistoryState.empty : HistoryState.loaded;
      });
    } catch (error) {
      setState(() {
        _error = 'Не удалось загрузить заказы. Проверьте интернет и попробуйте снова.';
        _state = HistoryState.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Convert Order objects to _HistoryOrder for UI display
    final orders = _orders.map((order) => _HistoryOrder.fromOrder(order)).toList();

    return Scaffold(
      backgroundColor: AvroClientColors.background,
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
            color: AvroClientColors.textPrimary,
            size: 20,
          ),
          splashRadius: 24,
          padding: const EdgeInsets.all(8),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                _state == HistoryState.loaded
                    ? '${orders.length} поездки'
                    : '',
                style: EvikTypography.bodyMedium.copyWith(
                  color: AvroClientColors.textSecondary,
                ),
              ),
            ),
            const Divider(height: 1, color: AvroClientColors.surface),
            Expanded(child: _buildBody(orders)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(List<_HistoryOrder> orders) {
    switch (_state) {
      case HistoryState.loading:
        return ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 100),
          itemCount: 5,
          itemBuilder: (_, __) => const SkeletonCard(height: 116),
        );
      case HistoryState.empty:
        return EmptyState(
          icon: Icons.history_outlined,
          title: 'Пока заказов нет',
          subtitle: 'Создайте первый заказ эвакуатора',
          buttonText: 'Создать заказ',
          onButtonTap: widget.onSwitchToHome,
        );
      case HistoryState.error:
        return ErrorState(
          message: _error ?? 'История заказов временно недоступна.',
          onRetry: _loadOrders,
        );
      case HistoryState.loaded:
        return ListView.separated(
          scrollCacheExtent: ScrollCacheExtent.pixels(200),
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 100),
          itemBuilder: (context, index) => AnimatedListItem(
            index: index,
            child: _HistoryCard(order: orders[index], realOrder: _orders[index]),
          ),
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemCount: orders.length,
        );
    }
  }
}

class _HistoryCard extends ConsumerWidget {
  const _HistoryCard({required this.order, required this.realOrder});

  final _HistoryOrder order;
  final Order realOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: AvroClientColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AvroClientColors.surface),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.dateText,
                      style: EvikTypography.bodySmall
                          .copyWith(color: AvroClientColors.textSecondary),
                    ),
                    const SizedBox(height: 2),
                    Text(order.car,
                        style: EvikTypography.bodyLarge
                            .copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(order.priceText,
                      style: EvikTypography.h3.copyWith(
                          fontSize: 34 / 2, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: order.statusColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      order.status,
                      style: EvikTypography.bodySmall.copyWith(
                        color: order.statusColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _RouteRow(color: AvroClientColors.accent, text: order.from),
          const SizedBox(height: 6),
          _RouteRow(color: AvroClientColors.textPrimary, text: order.to),
          const SizedBox(height: 10),
          const Divider(height: 1, color: AvroClientColors.surface),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  order.driver,
                  style: EvikTypography.bodyMedium
                      .copyWith(color: AvroClientColors.textSecondary),
                ),
              ),
              if (order.rating > 0)
                Row(
                  children: List.generate(
                    5,
                    (index) => Icon(
                      index < order.rating ? Icons.star : Icons.star_border,
                      size: 16,
                      color: AvroClientColors.warning,
                    ),
                  ),
                ),
            ],
          ),
          // Review section for completed orders
          if (realOrder.status == OrderStatus.completed) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: AvroClientColors.surface),
            const SizedBox(height: 12),
            _ReviewSection(orderId: realOrder.id),
          ],
        ],
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  const _RouteRow({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style:
                EvikTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _HistoryOrder {
  const _HistoryOrder({
    required this.dateText,
    required this.car,
    required this.from,
    required this.to,
    required this.driver,
    required this.priceText,
    required this.status,
    required this.statusColor,
    required this.rating,
  });

  final String dateText;
  final String car;
  final String from;
  final String to;
  final String driver;
  final String priceText;
  final String status;
  final Color statusColor;
  final int rating;

  /// Convert real Order data to UI display format
  factory _HistoryOrder.fromOrder(Order order) {
    // Format date
    final dateText = '${order.createdAt.day} ${_getMonthName(order.createdAt.month)}, ${order.createdAt.hour.toString().padLeft(2, '0')}:${order.createdAt.minute.toString().padLeft(2, '0')}';

    // Vehicle type display
    String car = '';
    switch (order.vehicleType) {
      case VehicleType.light:
        car = 'Легковой автомобиль';
        break;
      case VehicleType.suv:
        car = 'Внедорожник';
        break;
      case VehicleType.minibus:
        car = 'Минивэн';
        break;
      case VehicleType.truck:
        car = 'Грузовой автомобиль';
        break;
    }

    // Status display and color
    String statusText;
    Color statusColor;
    switch (order.status) {
      case OrderStatus.awaitingPayment:
        statusText = 'Ожидает оплаты';
        statusColor = AvroClientColors.warning;
        break;
      case OrderStatus.completed:
        statusText = 'Завершён';
        statusColor = AvroClientColors.success;
        break;
      case OrderStatus.cancelled:
        statusText = 'Отменён';
        statusColor = AvroClientColors.error;
        break;
      case OrderStatus.searching:
      case OrderStatus.assigned:
      case OrderStatus.onWay:
      case OrderStatus.arrived:
      case OrderStatus.evacuating:
        statusText = 'В работе';
        statusColor = AvroClientColors.info;
        break;
    }

    // Price formatting
    final price = order.finalPrice ?? order.estimatedPrice;
    final priceText = '${price.toStringAsFixed(0)} ₽';

    return _HistoryOrder(
      dateText: dateText,
      car: car,
      from: order.pickupLocation.address,
      to: order.dropoffLocation.address,
      driver: 'Водитель',
      priceText: priceText,
      status: statusText,
      statusColor: statusColor,
      rating: 0, // Will be filled when we have rating data
    );
  }

  static String _getMonthName(int month) {
    const months = [
      'янв', 'фев', 'мар', 'апр', 'мая', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'
    ];
    return months[month - 1];
  }
}

class _ReviewSection extends ConsumerWidget {
  const _ReviewSection({required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewAsync = ref.watch(orderReviewProvider(orderId));

    return reviewAsync.when(
      loading: () => const SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (error, stack) => const SizedBox.shrink(), // Hide on error
      data: (review) {
        if (review != null) {
          // Show existing review
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Ваш отзыв:',
                    style: EvikTypography.bodySmall.copyWith(
                      color: AvroClientColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ...List.generate(5, (index) {
                    return Icon(
                      index < review.stars ? Icons.star : Icons.star_border,
                      size: 14,
                      color: AvroClientColors.warning,
                    );
                  }),
                ],
              ),
              if (review.text.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  review.text,
                  style: EvikTypography.bodySmall.copyWith(
                    color: AvroClientColors.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          );
        } else {
          // Show "Leave Review" button
          return SizedBox(
            width: double.infinity,
            height: 32,
            child: EvikButton(
              text: 'Оставить отзыв',
              onPressed: () {
                // Navigate to rating screen
                context.go('/rate-driver');
              },
              variant: EvikButtonVariant.ghost,
            ),
          );
        }
      },
    );
  }
}
