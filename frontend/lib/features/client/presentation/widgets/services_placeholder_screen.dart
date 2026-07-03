import 'package:flutter/material.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroClientColors;

/// Заглушка вкладки «Услуги» в нижней навигации клиента.
/// Полноценный каталог услуг появится позже.
class ServicesPlaceholderScreen extends StatelessWidget {
  const ServicesPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AvroClientColors.background,
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
                    color: AvroClientColors.background,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AvroClientColors.surface),
                  ),
                  child: const Icon(
                    Icons.grid_view_rounded,
                    size: 40,
                    color: AvroClientColors.accent,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Услуги',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AvroClientColors.textPrimary,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Шиномонтаж, автоэлектрик, подвоз топлива\nи другие услуги появятся совсем скоро',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: AvroClientColors.textSecondary,
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
