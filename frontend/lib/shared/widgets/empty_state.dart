import 'package:flutter/material.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart'
    show AvroClientColors, AvroDriverColors;
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';
import 'evik_button.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.buttonText,
    this.onButtonTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? buttonText;
  final VoidCallback? onButtonTap;

  @override
  Widget build(BuildContext context) {
    final hasButton = buttonText != null && onButtonTap != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText =
        isDark ? AvroDriverColors.textPrimary : AvroClientColors.textPrimary;
    final secondaryText =
        isDark ? AvroDriverColors.grayHint : AvroClientColors.tabInactive;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: isDark
                    ? AvroDriverColors.surface
                    : AvroClientColors.background,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: secondaryText),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: EvikTypography.h3.copyWith(
                fontSize: 20,
                color: primaryText,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: EvikTypography.bodyMedium.copyWith(
                color: secondaryText,
              ),
              textAlign: TextAlign.center,
            ),
            if (hasButton) ...[
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: EvikButton(
                  text: buttonText!,
                  onPressed: onButtonTap,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
