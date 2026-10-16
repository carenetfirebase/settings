import 'dart:ui';

/// Chefii brand palette — "Quiet Luxury".
abstract final class ChefiiColors {
  static const porcelain = Color(0xFFF7F4EE);
  static const ivory = Color(0xFFFFFDF9);
  static const sage = Color(0xFFD6DDC6);
  static const forest = Color(0xFF344439);
  /// Brand champagne: logo, icon, splash and large decorative use only.
  static const champagne = Color(0xFFB69B72);

  /// Antique gold: the in-app accent for text and icons (≥4.5:1 on every
  /// light surface; champagne is only 2.4:1).
  static const champagneDeep = Color(0xFF7A6240);
  static const ink = Color(0xFF252922);

  /// Secondary text. ≥4.5:1 (WCAG AA) on porcelain, ivory and all soft fills.
  static const muted = Color(0xFF5C6158);

  // Derived neutrals.
  static const hairline = Color(0xFFE6E1D6);
  static const sageSoft = Color(0xFFEBEFE2);
  static const champagneSoft = Color(0xFFF1E9DC);

  // Semantic colours (WCAG AA on porcelain/ivory for text use).
  static const success = Color(0xFF2E6A47);
  static const successSoft = Color(0xFFE2EEE5);
  static const warning = Color(0xFF8A5A0B);
  static const warningSoft = Color(0xFFF6EBD7);
  static const error = Color(0xFFA23B32);
  static const errorSoft = Color(0xFFF6E1DE);
  static const info = Color(0xFF34556E);
  static const infoSoft = Color(0xFFE1E9EF);

  // Dark appearance.
  static const darkBackground = Color(0xFF151815);
  static const darkSurface = Color(0xFF1E231F);
  static const darkSurfaceHigh = Color(0xFF283029);
  static const darkInk = Color(0xFFEFEADF);
  static const darkMuted = Color(0xFFA7AC9F);
  static const darkPrimary = Color(0xFFA9C3AE);
  static const darkHairline = Color(0xFF353C36);
}

/// 8-point spacing scale.
abstract final class Space {
  static const double xxs = 4;
  static const double xs = 8;
  static const double s = 12;
  static const double m = 16;
  static const double l = 24;
  static const double xl = 32;
  static const double xxl = 48;
  static const double xxxl = 64;

  /// Horizontal page gutter.
  static const double gutter = 24;
}

abstract final class Radii {
  static const double s = 10;
  static const double m = 16;
  static const double l = 24;
  static const double xl = 32;
}

/// Minimum interactive size (Material/Apple HIG ≥ 44–48 dp).
const double kMinTouchTarget = 48;

/// Motion: subtle, purposeful.
abstract final class Motion {
  static const fast = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 260);
  static const slow = Duration(milliseconds: 420);
}
