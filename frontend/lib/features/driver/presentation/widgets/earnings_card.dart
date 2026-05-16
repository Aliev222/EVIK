import 'package:flutter/material.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver_earnings.dart';

class EarningsCard extends StatelessWidget {
  const EarningsCard({
    super.key,
    required this.stats,
    this.compact = false,
    this.onTap,
  });

  final EarningsStats stats;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE4E7EC)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined,
                  color: EvikColors.textPrimaryDark),
              const SizedBox(width: 8),
              Text(
                compact ? 'Сегодня' : 'Заработок',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: EvikColors.textPrimaryDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: stats.today),
            duration: const Duration(milliseconds: 450),
            builder: (context, value, _) {
              return Text(
                '${value.toStringAsFixed(0)}₽',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: EvikColors.textPrimaryDark,
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          Text(
            'Сегодня: ${stats.ordersToday} заказа • ${stats.averageRating.toStringAsFixed(1)} ⭐',
            style: const TextStyle(
              fontSize: 13,
              color: EvikColors.textSecondaryDark,
            ),
          ),
          if (!compact) ...[
            const SizedBox(height: 8),
            Text(
              'Эта неделя: ${stats.ordersWeek} заказов • ${stats.week.toStringAsFixed(0)}₽',
              style: const TextStyle(
                fontSize: 14,
                color: EvikColors.textSecondaryDark,
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) {
      return content;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: content,
    );
  }
}
