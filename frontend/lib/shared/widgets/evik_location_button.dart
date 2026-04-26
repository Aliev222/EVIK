import 'package:flutter/material.dart';
import '../../core/theme/evik_colors.dart';

class EvikLocationButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isLoading;

  const EvikLocationButton({
    super.key,
    this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 14,
      bottom: 90, // Над CTA кнопкой
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: EvikColors.primaryWhite,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isLoading ? null : onPressed,
            borderRadius: BorderRadius.circular(12),
            child: Center(
              child: isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        EvikColors.accentOrange,
                      ),
                    ),
                  )
                : const Icon(
                    Icons.navigation_rounded,
                    size: 19,
                    color: EvikColors.accentOrange,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}