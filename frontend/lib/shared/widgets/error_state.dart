import 'package:flutter/material.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroClientColors;
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';
import 'evik_button.dart';

class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.message,
    required this.onRetry,
    this.retryText = 'Попробовать снова',
  });

  final String message;
  final VoidCallback onRetry;
  final String retryText;

  @override
  Widget build(BuildContext context) {
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
                color: AvroClientColors.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline,
                size: 40,
                color: AvroClientColors.error,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Не удалось загрузить данные',
              style: EvikTypography.h3.copyWith(
                fontSize: 20,
                color: AvroClientColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: EvikTypography.bodyMedium.copyWith(
                color: AvroClientColors.tabInactive,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: EvikButton(
                text: retryText,
                onPressed: onRetry,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
