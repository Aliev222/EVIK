import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class EvikTypography {
  static String get fontFamily => GoogleFonts.inter().fontFamily!;

  static TextStyle get h1 => GoogleFonts.inter(
    fontSize: 40,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.03,
    height: 1.08,
  );

  static TextStyle get h2 => GoogleFonts.inter(
    fontSize: 26,
    fontWeight: FontWeight.w800,
    height: 1.2,
  );

  static TextStyle get h3 => GoogleFonts.inter(
    fontSize: 20,
    fontWeight: FontWeight.w800,
  );

  static TextStyle get bodyLarge => GoogleFonts.inter(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.65,
  );

  static TextStyle get bodyMedium => GoogleFonts.inter(
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );

  static TextStyle get bodySmall => GoogleFonts.inter(
    fontSize: 11,
    fontWeight: FontWeight.w500,
  );

  static TextStyle get caption => GoogleFonts.inter(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.08,
  );

  static TextStyle get buttonText => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.01,
  );

  static TextStyle get buttonTextSmall => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.01,
  );

  static TextStyle get sectionLabel => GoogleFonts.inter(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.08,
  );

  static TextStyle get price => GoogleFonts.inter(
    fontSize: 20,
    fontWeight: FontWeight.w800,
  );
}
