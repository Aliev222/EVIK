import 'package:flutter/material.dart';

class AvroClientColors {
  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFE3E3E3);
  static const Color accent = Color(0xFFFF7B42);
  static const Color accentStrong = Color(0xFFC2410C);
  static const Color accentDeep = Color(0xFFB45309);
  static const Color textPrimary = Color(0xFF000000);
  static const Color textSecondary = Color(0xFF212121);
  static const Color navBar = Color(0xFFFFFFFF);
  static const Color tabActive = Color(0xFFFF4000);
  static const Color tabInactive = Color(0xFFAAAAAA);

  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);
  static const Color sosRed = Color(0xFFDC2626);
}

class AvroDriverColors {
  static const Color background = Color(0xFF1F1F1F);
  static const Color surface = Color(0xFF1E1E1E);
  static const Color accent = Color(0xFF4ADE80);
  static const Color textPrimary = Color(0xFFF5F5F5);
  static const Color textSecondary = Color(0xFFA1A1AA);
  static const Color navBar = Color(0xFF1A1A1A);
  static const Color tabActive = Color(0xFF4ADE80);
  static const Color tabInactive = Color(0xFF555555);

  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);
  static const Color sosRed = Color(0xFFDC2626);

  static const Color documentBg = Color(0xFFF7F4EF);
  static const Color documentCard = Color(0xFFE2DDD5);
  static const Color documentBorder = Color(0xFFD8D2C7);
  static const Color documentDivider = Color(0xFFF1EEE8);
  static const Color documentDisabled = Color(0xFFCBC7BE);

  static const Color errorBg = Color(0xFFFFF2F0);
  static const Color errorBorder = Color(0xFFFFD3CB);
  static const Color errorText = Color(0xFFB3261E);

  static const Color border = Color(0xFF333333);
  static const Color borderLight = Color(0xFFE4E7EC);
  static const Color grayHint = Color(0xFF98A2B3);
  static const Color graySubtle = Color(0xFF667085);
  static const Color darkBlue = Color(0xFF101828);
}

@Deprecated('Use AvroClientColors or AvroDriverColors')
class EvikColors {
  static const Color accentOrange = AvroClientColors.accent;
  static const Color primaryBlack = AvroClientColors.textPrimary;
  static const Color primaryWhite = AvroClientColors.background;
  static const Color accentOrangeAction = AvroClientColors.accent;

  static const Color textPrimary = AvroClientColors.textPrimary;
  static const Color textSecondary = AvroClientColors.textSecondary;
  static const Color textHint = AvroClientColors.tabInactive;
  static const Color surface = AvroClientColors.surface;
  static const Color cardBackground = AvroClientColors.surface;
  static const Color border = AvroClientColors.surface;
  static const Color sosRed = AvroClientColors.sosRed;

  static const Color successGreen = AvroClientColors.success;
  static const Color warningAmber = AvroClientColors.warning;
  static const Color errorRed = AvroClientColors.error;
  static const Color infoBlue = AvroClientColors.info;

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
