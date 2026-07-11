import 'package:flutter/material.dart';

import 'package:tow_truck_frontend/core/format/money.dart';
import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroDriverColors;
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver_earnings.dart';

class EarningsCard extends StatelessWidget {
  const EarningsCard({
    super.key,
    required this.stats,
    this.compact = false,
    this.onTap,
    this.errorMessage,
    this.onRetry,
  });

  final EarningsStats stats;
  final bool compact;
  final VoidCallback? onTap;
  final String? errorMessage;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AvroDriverColors.borderLight),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: errorMessage != null ? _errorContent() : _statsContent(),
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

  Widget _statsContent() {
    final rublesToday = stats.todayAmount / 100.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.account_balance_wallet_outlined,
                color: AvroDriverColors.textPrimary),
            const SizedBox(width: 8),
            Text(
              compact ? 'Сегодня' : 'Заработок',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AvroDriverColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: rublesToday),
          duration: const Duration(milliseconds: 450),
          builder: (context, value, _) {
            final display = value.toStringAsFixed(0);
            return Text(
              '$display ₽',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AvroDriverColors.textPrimary,
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        Text(
          'Сегодня: ${stats.todayOrders} заказа • ${stats.ratingAverage.toStringAsFixed(1)} ⭐',
          style: const TextStyle(
            fontSize: 13,
            color: AvroDriverColors.textSecondary,
          ),
        ),
        if (!compact) ...[
          const SizedBox(height: 8),
          Text(
            'Эта неделя: ${stats.weekOrders} заказов • ${formatKopecks(stats.weekAmount)}',
            style: const TextStyle(
              fontSize: 14,
              color: AvroDriverColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }

  Widget _errorContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AvroDriverColors.error.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: AvroDriverColors.error, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  errorMessage!,
                  style: EvikTypography.bodySmall.copyWith(
                    color: AvroDriverColors.error,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Повторить'),
            ),
          ),
        ],
      ],
    );
  }
}
