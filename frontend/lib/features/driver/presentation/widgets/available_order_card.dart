import 'package:flutter/material.dart';
import '../../../../core/theme/evik_colors.dart';
import '../../../../core/theme/evik_typography.dart';
import '../../../../shared/widgets/evik_button.dart';
import '../../domain/entities/available_order.dart';

class AvailableOrderCard extends StatelessWidget {
  final AvailableOrder order;
  final VoidCallback onAccept;

  const AvailableOrderCard({
    super.key,
    required this.order,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EvikColors.primaryWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EvikColors.gray200, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                order.vehicleIcon,
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${order.vehicleDisplayName} • ${order.vehicleModel}',
                  style: EvikTypography.bodyMedium.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getSeverityColor().withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  order.problemType,
                  style: EvikTypography.bodySmall.copyWith(
                    color: _getSeverityColor(),
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Адреса
          _buildAddressRow('📍', order.pickupAddress, isPickup: true),
          const SizedBox(height: 6),
          _buildAddressRow('🏁', order.dropoffAddress, isPickup: false),

          const SizedBox(height: 16),

          // Метрики и кнопка
          Row(
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 16,
                color: EvikColors.accentOrange,
              ),
              const SizedBox(width: 4),
              Text(
                '${order.distanceKm.toStringAsFixed(1)} км',
                style: EvikTypography.bodySmall.copyWith(
                  color: EvikColors.gray500,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 16),
              const Icon(
                Icons.access_time_rounded,
                size: 16,
                color: EvikColors.gray500,
              ),
              const SizedBox(width: 4),
              Text(
                '${order.estimatedMinutes} мин',
                style: EvikTypography.bodySmall.copyWith(
                  color: EvikColors.gray500,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              Text(
                '${order.price.toInt()} ₽',
                style: EvikTypography.price.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 16),
              EvikButton(
                text: 'Принять',
                onPressed: onAccept,
                small: true,
                variant: EvikButtonVariant.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAddressRow(String emoji, String address,
      {required bool isPickup}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            address,
            style: EvikTypography.bodyMedium.copyWith(
              fontSize: 13,
              color: EvikColors.gray800,
            ),
          ),
        ),
      ],
    );
  }

  Color _getSeverityColor() {
    switch (order.severity) {
      case ProblemSeverity.low:
        return EvikColors.warningAmber;
      case ProblemSeverity.medium:
        return EvikColors.infoBlue;
      case ProblemSeverity.high:
        return EvikColors.errorRed;
    }
  }
}
