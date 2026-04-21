import 'package:flutter/material.dart';

import '../theme/evik_colors.dart';
import '../theme/evik_tokens.dart';

class AppStateCard extends StatelessWidget {
  const AppStateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.footer,
    this.accentColor = EvikColors.accent,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final Widget? footer;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          padding: const EdgeInsets.all(EvikSpacing.xl),
          decoration: BoxDecoration(
            color: EvikColors.surfaceDark,
            borderRadius: BorderRadius.circular(EvikRadii.xl),
            border: Border.all(color: EvikColors.borderDark),
            boxShadow: EvikShadows.floating,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(EvikRadii.md),
                ),
                child: Icon(icon, color: accentColor, size: 28),
              ),
              const SizedBox(height: EvikSpacing.lg),
              Text(title, style: theme.textTheme.headlineMedium),
              const SizedBox(height: EvikSpacing.xs),
              Text(
                subtitle,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: EvikColors.textSecondaryDark,
                  height: 1.45,
                ),
              ),
              if (footer != null) ...[
                const SizedBox(height: EvikSpacing.lg),
                footer!,
              ],
              if (primaryLabel != null && onPrimary != null) ...[
                const SizedBox(height: EvikSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onPrimary,
                    child: Text(primaryLabel!),
                  ),
                ),
              ],
              if (secondaryLabel != null && onSecondary != null) ...[
                const SizedBox(height: EvikSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: onSecondary,
                    child: Text(secondaryLabel!),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
