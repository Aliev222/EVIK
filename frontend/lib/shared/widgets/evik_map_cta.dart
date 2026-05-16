import 'package:flutter/material.dart';
import 'package:tow_truck_frontend/core/theme/evik_colors.dart';
import 'evik_button.dart';

class EvikMapCTA extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Widget? icon;

  const EvikMapCTA({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              EvikColors.primaryWhite.withValues(alpha: 0.0),
              EvikColors.primaryWhite.withValues(alpha: 0.65),
              EvikColors.primaryWhite,
            ],
            stops: const [0.0, 0.35, 1.0],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: SafeArea(
          top: false,
          child: EvikButton(
            text: text,
            onPressed: isLoading ? null : onPressed,
            isLoading: isLoading,
            icon: icon,
            width: double.infinity,
          ),
        ),
      ),
    );
  }

  // Предустановленные варианты
  factory EvikMapCTA.callTowTruck(VoidCallback? onPressed) => EvikMapCTA(
        text: '🚛 Вызвать эвакуатор',
        onPressed: onPressed,
      );

  factory EvikMapCTA.searching() => const EvikMapCTA(
        text: 'Ищем водителя...',
        isLoading: true,
      );

  factory EvikMapCTA.confirmLocation(VoidCallback? onPressed) => EvikMapCTA(
        text: 'Подтвердить место',
        onPressed: onPressed,
      );

  factory EvikMapCTA.createOrder(VoidCallback? onPressed) => EvikMapCTA(
        text: 'Заказать эвакуатор',
        onPressed: onPressed,
      );
}
