import 'package:flutter/material.dart';

import '../../../../core/theme/evik_colors.dart';
import '../../../../core/theme/evik_typography.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_state.dart';
import '../../../../shared/widgets/animated_list_item.dart';
import '../../../../shared/widgets/skeleton_card.dart';

enum HistoryState { loading, empty, loaded, error }

class ClientHistoryScreen extends StatefulWidget {
  const ClientHistoryScreen({super.key, this.onSwitchToHome});

  final VoidCallback? onSwitchToHome;

  @override
  State<ClientHistoryScreen> createState() => _ClientHistoryScreenState();
}

class _ClientHistoryScreenState extends State<ClientHistoryScreen> {
  HistoryState _state = HistoryState.loaded;

  @override
  Widget build(BuildContext context) {
    final orders = <_HistoryOrder>[
      const _HistoryOrder(
        dateText: '23 апр, 14:32',
        car: 'Toyota Camry',
        from: 'ул. Тверская, 15',
        to: 'СТО Автодром, Ленинский пр.',
        driver: 'Михаил С.',
        priceText: '2 300 ₽',
        status: 'Завершён',
        statusColor: Color(0xFF10B981),
        rating: 5,
      ),
      const _HistoryOrder(
        dateText: '19 апр, 09:14',
        car: 'BMW X5',
        from: 'Садовое кольцо, 28',
        to: 'Паркинг Охотный Ряд',
        driver: 'Алексей В.',
        priceText: '1 800 ₽',
        status: 'Завершён',
        statusColor: Color(0xFF10B981),
        rating: 4,
      ),
      const _HistoryOrder(
        dateText: '11 апр, 18:55',
        car: 'KIA Sportage',
        from: 'ш. Энтузиастов, 3',
        to: 'Дилерский центр KIA',
        driver: '',
        priceText: '3 100 ₽',
        status: 'Отменён',
        statusColor: Color(0xFFEF4444),
        rating: 0,
      ),
      const _HistoryOrder(
        dateText: '2 апр, 11:20',
        car: 'Lada Vesta',
        from: 'ул. Профсоюзная, 110',
        to: 'Технический центр Сити',
        driver: 'Денис П.',
        priceText: '2 700 ₽',
        status: 'Завершён',
        statusColor: Color(0xFF10B981),
        rating: 5,
      ),
    ];

    return Scaffold(
      backgroundColor: EvikColors.gray50,
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
            color: EvikColors.primaryBlack,
            size: 20,
          ),
          splashRadius: 24,
          padding: const EdgeInsets.all(8),
        ),
        actions: [
          _StateAction(
            label: 'Empty',
            onTap: () => setState(() => _state = HistoryState.empty),
          ),
          _StateAction(
            label: 'Loading',
            onTap: () => setState(() => _state = HistoryState.loading),
          ),
          _StateAction(
            label: 'Error',
            onTap: () => setState(() => _state = HistoryState.error),
          ),
          _StateAction(
            label: 'Loaded',
            onTap: () => setState(() => _state = HistoryState.loaded),
          ),
        ],
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
                    : 'MOCK состояния для проверки UI',
                style: EvikTypography.bodyMedium.copyWith(
                  color: EvikColors.gray600,
                ),
              ),
            ),
            const Divider(height: 1, color: EvikColors.gray200),
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
          message: 'История заказов временно недоступна.',
          onRetry: () => setState(() => _state = HistoryState.loading),
        );
      case HistoryState.loaded:
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 100),
          cacheExtent: 200,
          itemBuilder: (context, index) => AnimatedListItem(
            index: index,
            child: _HistoryCard(order: orders[index]),
          ),
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemCount: orders.length,
        );
    }
  }
}

class _StateAction extends StatelessWidget {
  const _StateAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      child: Text(
        label,
        style: EvikTypography.bodySmall.copyWith(
          color: EvikColors.accentOrange,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.order});

  final _HistoryOrder order;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: EvikColors.primaryWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EvikColors.gray200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
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
                          .copyWith(color: EvikColors.gray500),
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
          _RouteRow(color: EvikColors.accentOrange, text: order.from),
          const SizedBox(height: 6),
          _RouteRow(color: EvikColors.primaryBlack, text: order.to),
          const SizedBox(height: 10),
          const Divider(height: 1, color: EvikColors.gray200),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  order.driver,
                  style: EvikTypography.bodyMedium
                      .copyWith(color: EvikColors.gray500),
                ),
              ),
              if (order.rating > 0)
                Row(
                  children: List.generate(
                    5,
                    (index) => Icon(
                      index < order.rating ? Icons.star : Icons.star_border,
                      size: 16,
                      color: const Color(0xFFF59E0B),
                    ),
                  ),
                ),
            ],
          ),
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
}
