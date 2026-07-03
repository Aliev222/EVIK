import 'package:flutter/material.dart';
import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroClientColors;
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';

class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final bool small;

  const StatusPill({
    super.key,
    required this.label,
    this.color = AvroClientColors.warning,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: small
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 3)
        : const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: EvikTypography.caption.copyWith(
          color: color,
          fontSize: small ? 10 : 12,
        ),
      ),
    );
  }

  // Предустановленные статусы
  factory StatusPill.pending() => const StatusPill(
    label: 'Ожидание',
    color: AvroClientColors.warning,
  );

  factory StatusPill.approved() => const StatusPill(
    label: 'Одобрено',
    color: AvroClientColors.success,
  );

  factory StatusPill.rejected() => const StatusPill(
    label: 'Отклонено',
    color: AvroClientColors.error,
  );

  factory StatusPill.searching() => const StatusPill(
    label: 'Поиск',
    color: AvroClientColors.warning,
  );

  factory StatusPill.enRoute() => const StatusPill(
    label: 'В пути',
    color: AvroClientColors.info,
  );

  factory StatusPill.arrived() => const StatusPill(
    label: 'На месте',
    color: AvroClientColors.success,
  );

  factory StatusPill.completed() => const StatusPill(
    label: 'Завершено',
    color: AvroClientColors.success,
  );

  factory StatusPill.cancelled() => const StatusPill(
    label: 'Отменено',
    color: AvroClientColors.error,
  );
}
