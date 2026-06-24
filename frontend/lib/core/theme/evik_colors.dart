import 'package:flutter/material.dart';

class EvikColors {
  // Основные цвета
  static const Color primaryBlack = Color(0xFF111111);
  static const Color primaryWhite = Color(0xFFFFFFFF);
  static const Color accentOrange = Color(0xFFFF6B00);
  // Затемнённый оранжевый для поверхностей с белым текстом (контраст ≥ 4.5:1)
  static const Color accentOrangeAction = Color(0xFFE25E00);

  // Семантические цвета единой палитры
  static const Color textPrimary = Color(0xFF111111);
  static const Color textSecondary = Color(0xFF555555);
  static const Color textHint = Color(0xFFAAAAAA);
  static const Color surface = Color(0xFFF7F7F7);
  static const Color cardBackground = surface;
  static const Color border = Color(0xFFEEEEEE);
  static const Color sosRed = Color(0xFFEF4444);

  // Функциональные цвета
  static const Color successGreen = Color(0xFF22C55E);
  static const Color warningAmber = Color(0xFFF59E0B);
  static const Color errorRed = Color(0xFFEF4444);
  static const Color infoBlue = Color(0xFF3B82F6);

  // Нейтральная палитра
  static const Color gray50 = Color(0xFFF9FAFB);
  static const Color gray100 = Color(0xFFF3F4F6);
  static const Color gray200 = Color(0xFFE5E7EB);
  static const Color gray300 = Color(0xFFD1D5DB);
  static const Color gray400 = Color(0xFF9CA3AF);
  static const Color gray500 = Color(0xFF6B7280);
  static const Color gray600 = Color(0xFF4B5563);
  static const Color gray700 = Color(0xFF374151);
  static const Color gray800 = Color(0xFF1F2937);
  static const Color gray900 = Color(0xFF111827);

  // Обратная совместимость с существующим кодом
  static const Color lightBackground = gray50;
  static const Color darkBackground = primaryBlack;
  static const Color surfaceDark = primaryWhite;
  static const Color surfaceLight = gray900;
  static const Color borderDark = gray200;
  static const Color borderLight = gray800;
  static const Color textPrimaryDark = primaryBlack;
  static const Color textPrimaryLight = primaryWhite;
  static const Color textSecondaryDark = gray500;
  static const Color textSecondaryLight = gray300;
  static const Color accent = accentOrange;
  static const Color accentPressed = Color(0xFFE55C2B);
  static const Color danger = errorRed;

  static const LinearGradient mapFallbackGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[Color(0xFFE8F0E4), Color(0xFFF0F5F0), Color(0xFFE8F0E4)],
  );
}
