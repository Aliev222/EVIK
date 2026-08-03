import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroClientColors;

/// Honest announcement of a planned feature: a short description of what it
/// will do plus its planned components, each marked with a subtle "скоро"
/// badge. Opens as a bottom sheet instead of pretending the tap did something.
class FeatureAnnouncementSheet extends StatelessWidget {
  const FeatureAnnouncementSheet({
    super.key,
    required this.title,
    required this.icon,
    required this.description,
    this.items = const [],
    this.accent = AvroClientColors.accent,
    this.background = AvroClientColors.background,
    this.itemBackground = AvroClientColors.surface,
    this.textPrimary = AvroClientColors.textPrimary,
    this.textSecondary = AvroClientColors.textSecondary,
    this.badge = AvroClientColors.tabInactive,
  });

  final String title;
  final IconData icon;
  final String description;
  final List<String> items;

  final Color accent;
  final Color background;
  final Color itemBackground;
  final Color textPrimary;
  final Color textSecondary;
  final Color badge;

  static void show(
    BuildContext context,
    FeatureAnnouncementSheet sheet,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => sheet,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: itemBackground,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, color: textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              description,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: textSecondary,
                height: 1.45,
              ),
            ),
            if (items.isNotEmpty) ...[
              const SizedBox(height: 16),
              ...items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: itemBackground,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: badge.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'скоро',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: badge,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
