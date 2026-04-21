import 'package:flutter/material.dart';

import 'evik_colors.dart';
import 'evik_tokens.dart';

class AppTheme {
  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: EvikColors.accent,
      surface: EvikColors.lightBackground,
      onSurface: EvikColors.textPrimaryDark,
      onPrimary: EvikColors.textPrimaryLight,
      error: EvikColors.danger,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: EvikColors.darkBackground,
      textTheme: base.textTheme.copyWith(
        headlineLarge: const TextStyle(
          color: EvikColors.textPrimaryDark,
          fontSize: 34,
          fontWeight: FontWeight.w700,
          height: 1.08,
          letterSpacing: -0.8,
        ),
        headlineMedium: const TextStyle(
          color: EvikColors.textPrimaryDark,
          fontSize: 26,
          fontWeight: FontWeight.w700,
          height: 1.14,
          letterSpacing: -0.4,
        ),
        titleLarge: const TextStyle(
          color: EvikColors.textPrimaryDark,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          height: 1.22,
        ),
        titleMedium: const TextStyle(
          color: EvikColors.textPrimaryDark,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          height: 1.22,
        ),
        bodyLarge: const TextStyle(
          color: EvikColors.textPrimaryDark,
          fontSize: 16,
          fontWeight: FontWeight.w500,
          height: 1.4,
        ),
        bodyMedium: const TextStyle(
          color: EvikColors.textPrimaryDark,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          height: 1.38,
        ),
        bodySmall: const TextStyle(
          color: EvikColors.textSecondaryDark,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          height: 1.35,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: EvikColors.textPrimaryDark,
        titleTextStyle: TextStyle(
          color: EvikColors.textPrimaryDark,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: EvikColors.surfaceLight,
        contentTextStyle: const TextStyle(
          color: EvikColors.textPrimaryLight,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EvikRadii.md),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          elevation: 0,
          shadowColor: Colors.transparent,
          backgroundColor: EvikColors.surfaceLight,
          foregroundColor: EvikColors.textPrimaryLight,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(EvikRadii.lg),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          foregroundColor: EvikColors.textPrimaryDark,
          side: const BorderSide(color: EvikColors.borderLight),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(EvikRadii.lg),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: EvikColors.textPrimaryDark,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: EvikColors.surfaceDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EvikRadii.xl),
          side: const BorderSide(color: EvikColors.borderDark),
        ),
      ),
      dividerColor: EvikColors.borderDark,
      inputDecorationTheme: InputDecorationTheme(
        constraints: const BoxConstraints(minHeight: 56),
        filled: true,
        fillColor: EvikColors.surfaceDark,
        hintStyle: const TextStyle(
          color: EvikColors.textSecondaryDark,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EvikRadii.md),
          borderSide: const BorderSide(color: EvikColors.borderDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EvikRadii.md),
          borderSide: const BorderSide(color: EvikColors.borderDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EvikRadii.md),
          borderSide: const BorderSide(color: EvikColors.borderLight),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EvikRadii.md),
          borderSide: const BorderSide(color: EvikColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EvikRadii.md),
          borderSide: const BorderSide(color: EvikColors.danger),
        ),
      ),
    );
  }
}
