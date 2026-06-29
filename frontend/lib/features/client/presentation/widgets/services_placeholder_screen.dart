import 'package:flutter/material.dart';

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
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111111),
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Шиномонтаж, автоэлектрик, подвоз топлива\nи другие услуги появятся совсем скоро',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF555555),
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
