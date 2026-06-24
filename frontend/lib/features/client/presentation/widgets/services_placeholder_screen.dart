import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart';

/// Заглушка вкладки «Услуги» в нижней навигации клиента.
/// Полноценный каталог услуг появится позже.
class ServicesPlaceholderScreen extends StatelessWidget {
  const ServicesPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EvikColors.primaryWhite,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: EvikColors.primaryWhite,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: EvikColors.border),
                  ),
                  child: const Icon(
                    Icons.grid_view_rounded,
                    size: 40,
                    color: EvikColors.accentOrange,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Услуги',
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: EvikColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Скоро будет доступно',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: EvikColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
