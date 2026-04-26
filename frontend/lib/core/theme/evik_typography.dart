import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'evik_colors.dart';

class EvikTypography {
  static String get fontFamily => GoogleFonts.manrope().fontFamily!;

  // Заголовки (точно как в Claude Design)
  static TextStyle get h1 => GoogleFonts.manrope(
    fontSize: 40,
    fontWeight: FontWeight.w800,
    color: EvikColors.primaryBlack,
    letterSpacing: -0.03,
    height: 1.08,
  );

  static TextStyle get h2 => GoogleFonts.manrope(
    fontSize: 26,
    fontWeight: FontWeight.w800,
    color: EvikColors.primaryBlack,
    height: 1.2,
  );

  static TextStyle get h3 => GoogleFonts.manrope(
    fontSize: 20,
    fontWeight: FontWeight.w800,
    color: EvikColors.primaryBlack,
  );

  // Основной текст
  static TextStyle get bodyLarge => GoogleFonts.manrope(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: EvikColors.primaryBlack,
    height: 1.65,
  );

  static TextStyle get bodyMedium => GoogleFonts.manrope(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: EvikColors.primaryBlack,
  );

  static TextStyle get bodySmall => GoogleFonts.manrope(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: EvikColors.gray500,
  );

  // Специальные стили
  static TextStyle get caption => GoogleFonts.manrope(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: EvikColors.gray500,
    letterSpacing: 0.08,
  );

  static TextStyle get buttonText => GoogleFonts.manrope(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.01,
  );

  static TextStyle get buttonTextSmall => GoogleFonts.manrope(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.01,
  );

  static TextStyle get sectionLabel => GoogleFonts.manrope(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    color: EvikColors.gray500,
    letterSpacing: 0.08,
  );

  static TextStyle get price => GoogleFonts.manrope(
    fontSize: 20,
    fontWeight: FontWeight.w800,
    color: EvikColors.accentOrange,
  );
}