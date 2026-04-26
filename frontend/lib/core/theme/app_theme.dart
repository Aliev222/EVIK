import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'evik_colors.dart';
import 'evik_tokens.dart';
import 'evik_typography.dart';

class AppTheme {
  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: EvikColors.accentOrange,
      surface: EvikColors.primaryWhite,
      onSurface: EvikColors.primaryBlack,
      onPrimary: EvikColors.primaryWhite,
      error: EvikColors.errorRed,
      secondary: EvikColors.gray800,
      onSecondary: EvikColors.primaryWhite,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: GoogleFonts.manrope().fontFamily,
      scaffoldBackgroundColor: EvikColors.gray50,
      textTheme: TextTheme(
        displayLarge: EvikTypography.h1,
        displayMedium: EvikTypography.h2,
        displaySmall: EvikTypography.h3,
        headlineLarge: EvikTypography.h1,
        headlineMedium: EvikTypography.h2,
        headlineSmall: EvikTypography.h3,
        titleLarge: EvikTypography.h3,
        titleMedium: EvikTypography.bodyLarge,
        titleSmall: EvikTypography.bodyMedium,
        bodyLarge: EvikTypography.bodyLarge,
        bodyMedium: EvikTypography.bodyMedium,
        bodySmall: EvikTypography.bodySmall,
        labelLarge: EvikTypography.buttonText,
        labelMedium: EvikTypography.buttonTextSmall,
        labelSmall: EvikTypography.caption,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: EvikColors.primaryWhite,
        elevation: 0,
        foregroundColor: EvikColors.primaryBlack,
        titleTextStyle: EvikTypography.h3,
        centerTitle: false,
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
          backgroundColor: EvikColors.accentOrange,
          foregroundColor: EvikColors.primaryWhite,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
          shadowColor: Colors.transparent,
          textStyle: EvikTypography.buttonText,
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
        color: EvikColors.primaryWhite,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      dividerColor: EvikColors.gray200,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: EvikColors.gray50,
        hintStyle: EvikTypography.bodyMedium.copyWith(
          color: EvikColors.gray500,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: EvikColors.gray200, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: EvikColors.gray200, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: EvikColors.accentOrange, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: EvikColors.errorRed, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: EvikColors.errorRed, width: 2),
        ),
      ),
    );
  }
}
