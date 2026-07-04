import 'package:flutter/material.dart';

class EvikSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 40;

  static const EdgeInsets screenPadding = EdgeInsets.symmetric(
    horizontal: xl,
    vertical: lg,
  );
}

class EvikRadii {
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;
}

class EvikDurations {
  static const Duration micro = Duration(milliseconds: 90);
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration medium = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 320);
}

class EvikCurves {
  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const Curve emphasized = Curves.easeInOutCubic;
}

class EvikShadows {
  static const List<BoxShadow> floating = <BoxShadow>[
    BoxShadow(
      color: Color(0x12000000),
      blurRadius: 22,
      offset: Offset(0, 10),
    ),
    BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 8,
      offset: Offset(0, 3),
    ),
  ];

  static List<BoxShadow> sm = <BoxShadow>[
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.06),
      blurRadius: 6,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> md = <BoxShadow>[
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.08),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.04),
      blurRadius: 4,
      offset: const Offset(0, 1),
    ),
  ];

  static List<BoxShadow> lg = <BoxShadow>[
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.10),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.06),
      blurRadius: 6,
      offset: const Offset(0, 3),
    ),
  ];

  static List<BoxShadow> sheet = <BoxShadow>[
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.12),
      blurRadius: 28,
      offset: const Offset(0, 12),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.06),
      blurRadius: 8,
      offset: const Offset(0, 4),
    ),
  ];
}

class EvikGlass {
  static const Color thin = Color(0xE6FFFFFF);
  static const Color light = Color(0xCCFFFFFF);
  static const Color medium = Color(0x99FFFFFF);
  static const Color darkThin = Color(0xE61A1A1A);
  static const Color darkLight = Color(0xCC1A1A1A);

  static BoxDecoration card({
    required Color background,
    required List<BoxShadow> shadows,
    double radius = 16,
  }) {
    return BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: shadows,
    );
  }

  static BoxDecoration glass({
    required Color color,
    double radius = 16,
    double blur = 12,
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
    );
  }
}
