import 'package:flutter/material.dart';

import 'package:tow_truck_frontend/core/format/money.dart';
import 'package:tow_truck_frontend/core/theme/evik_colors.dart'
    show AvroDriverColors;
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver_wallet.dart';
import 'package:tow_truck_frontend/features/driver/presentation/screens/driver_debt_screen.dart';

/// Banner shown to a driver who has debt, linking to the «Погасить долг»
/// screen. Turns red when the debt is at/above the configured threshold
/// (orders are blocked).
class DriverDebtBanner extends StatelessWidget {
  const DriverDebtBanner({required this.wallet, super.key});

  final DriverWallet wallet;

  @override
  Widget build(BuildContext context) {
    final debt = wallet.debtBalance;
    final blocked = wallet.debtBlocked;
    final color = blocked ? AvroDriverColors.error : AvroDriverColors.warning;

    final title = blocked
        ? 'Погасите долг ${formatKopecks(debt)}'
        : 'Долг за наличные: ${formatKopecks(debt)}';
    final subtitle = blocked
        ? 'Погасите долг, чтобы принимать заказы'
        : 'Карточные заказы погашают долг автоматически';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const DriverDebtScreen(),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                blocked ? Icons.payment_rounded : Icons.info_outline_rounded,
                size: 20,
                color: AvroDriverColors.background,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: EvikTypography.bodySmall.copyWith(
                        color: AvroDriverColors.background,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: EvikTypography.bodySmall.copyWith(
                        color: AvroDriverColors.background,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AvroDriverColors.background,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}