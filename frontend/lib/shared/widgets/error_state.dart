import 'package:flutter/material.dart';

import '../../core/theme/evik_colors.dart';
import '../../core/theme/evik_typography.dart';
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
                color: EvikColors.errorRed.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline,
                size: 40,
                color: EvikColors.errorRed,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Не удалось загрузить данные',
              style: EvikTypography.h3.copyWith(
                fontSize: 20,
                color: EvikColors.primaryBlack,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: EvikTypography.bodyMedium.copyWith(
                color: EvikColors.gray500,
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
