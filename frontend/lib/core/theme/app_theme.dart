import 'package:flutter/material.dart';

import 'evik_colors.dart';
import 'evik_tokens.dart';
import 'evik_typography.dart';

class AppTheme {
  static const String _fontFamily = 'Inter';

  static ThemeData client() {
    return ThemeData(
      useMaterial3: true,
      fontFamily: _fontFamily,
      scaffoldBackgroundColor: AvroClientColors.background,
      colorScheme: ColorScheme.light(
        primary: AvroClientColors.accent,
        surface: AvroClientColors.surface,
        onSurface: AvroClientColors.textPrimary,
        onPrimary: AvroClientColors.background,
        error: AvroClientColors.error,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AvroClientColors.navBar,
        foregroundColor: AvroClientColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: EvikTypography.h3,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AvroClientColors.navBar,
        selectedItemColor: AvroClientColors.tabActive,
        unselectedItemColor: AvroClientColors.tabInactive,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AvroClientColors.accentStrong,
          foregroundColor: AvroClientColors.background,
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
          foregroundColor: AvroClientColors.textPrimary,
          side: const BorderSide(color: AvroClientColors.surface),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(EvikRadii.lg),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: AvroClientColors.background,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      dividerColor: AvroClientColors.surface,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AvroClientColors.surface,
        hintStyle: EvikTypography.bodyMedium.copyWith(
          color: AvroClientColors.tabInactive,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AvroClientColors.surface, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AvroClientColors.surface, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AvroClientColors.accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AvroClientColors.error, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AvroClientColors.error, width: 2),
        ),
      ),
    );
  }

  static ThemeData driver() {
    return ThemeData(
      useMaterial3: true,
      fontFamily: _fontFamily,
      scaffoldBackgroundColor: AvroDriverColors.background,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: AvroDriverColors.accent,
        surface: AvroDriverColors.surface,
        onSurface: AvroDriverColors.textPrimary,
        onPrimary: AvroDriverColors.background,
        error: AvroDriverColors.error,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AvroDriverColors.navBar,
        foregroundColor: AvroDriverColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: EvikTypography.h3,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AvroDriverColors.navBar,
        selectedItemColor: AvroDriverColors.tabActive,
        unselectedItemColor: AvroDriverColors.grayHint,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AvroDriverColors.accent,
          foregroundColor: AvroDriverColors.background,
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
          foregroundColor: AvroDriverColors.textPrimary,
          side: const BorderSide(color: AvroDriverColors.surface),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(EvikRadii.lg),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: AvroDriverColors.surface,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      dividerColor: AvroDriverColors.border,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AvroDriverColors.surface,
        hintStyle: EvikTypography.bodyMedium.copyWith(
          color: AvroDriverColors.grayHint,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AvroDriverColors.border, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AvroDriverColors.border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AvroDriverColors.accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AvroDriverColors.error, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AvroDriverColors.error, width: 2),
        ),
      ),
    );
  }

  @Deprecated('Use client() or driver()')
  static ThemeData light() => client();
}
