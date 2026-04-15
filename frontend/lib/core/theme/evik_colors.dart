import 'package:flutter/material.dart';

class EvikColors {
  static const Color lightBackground = Color(0xFF1C1C1C);
  static const Color darkBackground = Color(0xFFE5E5E5);

  static const Color surfaceDark = Color(0xFFF2F2F2);
  static const Color surfaceLight = Color(0xFF232323);

  static const Color borderDark = Color(0xFFD3D3D3);
  static const Color borderLight = Color(0xFF343434);

  static const Color textPrimaryDark = Color(0xFF1C1C1C);
  static const Color textPrimaryLight = Color(0xFFF2F2F2);
  static const Color textSecondaryDark = Color(0xFF6C6C6C);
  static const Color textSecondaryLight = Color(0xFFA8A8A8);

  static const Color accent = Color(0xFF1C1C1C);
  static const Color accentPressed = Color(0xFF343434);
  static const Color danger = Color(0xFFB95A5A);

  static const LinearGradient mapFallbackGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[Color(0xFFEAEAEA), Color(0xFFF4F4F4), Color(0xFFEAEAEA)],
  );
}
