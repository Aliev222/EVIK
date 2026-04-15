import 'package:flutter/material.dart';

import 'evik_colors.dart';

class AppTheme {
  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: EvikColors.textPrimaryLight,
      surface: EvikColors.lightBackground,
      onSurface: EvikColors.textPrimaryLight,
      onPrimary: EvikColors.textPrimaryLight,
      error: EvikColors.danger,
    );

    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: EvikColors.darkBackground,
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: EvikColors.textPrimaryDark,
      ),
      dividerColor: EvikColors.borderDark,
      inputDecorationTheme: InputDecorationTheme(
        constraints: const BoxConstraints(minHeight: 56),
        filled: true,
        fillColor: EvikColors.surfaceDark,
        hintStyle:
            const TextStyle(color: EvikColors.textSecondaryDark, fontSize: 16),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: EvikColors.borderDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: EvikColors.borderLight),
        ),
      ),
    );
  }
}
