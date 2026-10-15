import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

TextStyle _serif(double size, {FontWeight weight = FontWeight.w500, double height = 1.1, double spacing = -0.2}) => TextStyle(
      fontFamily: 'Cormorant',
      fontSize: size,
      fontWeight: weight,
      fontVariations: [FontVariation.weight(weight.value.toDouble())],
      height: height,
      letterSpacing: spacing,
    );

TextStyle _sans(double size, {FontWeight weight = FontWeight.w400, double height = 1.45, double spacing = 0}) => TextStyle(
      fontFamily: 'Inter',
      fontSize: size,
      fontWeight: weight,
      fontVariations: [FontVariation.weight(weight.value.toDouble())],
      height: height,
      letterSpacing: spacing,
    );

/// Serif for editorial headlines (≥ 22 pt only — Cormorant is delicate at
/// small sizes), Inter for everything people read quickly or act on.
TextTheme _textTheme(Color ink, Color muted) => TextTheme(
      displayLarge: _serif(52, weight: FontWeight.w500, height: 1.02, spacing: -0.8).copyWith(color: ink),
      displayMedium: _serif(42, height: 1.05, spacing: -0.6).copyWith(color: ink),
      displaySmall: _serif(34, height: 1.08, spacing: -0.4).copyWith(color: ink),
      headlineLarge: _serif(32, weight: FontWeight.w600, height: 1.1).copyWith(color: ink),
      headlineMedium: _serif(28, weight: FontWeight.w600, height: 1.12).copyWith(color: ink),
      headlineSmall: _serif(24, weight: FontWeight.w600, height: 1.15).copyWith(color: ink),
      titleLarge: _sans(20, weight: FontWeight.w600, height: 1.3, spacing: -0.2).copyWith(color: ink),
      titleMedium: _sans(16, weight: FontWeight.w600, height: 1.35).copyWith(color: ink),
      titleSmall: _sans(14, weight: FontWeight.w600, height: 1.35).copyWith(color: ink),
      bodyLarge: _sans(17, height: 1.5).copyWith(color: ink),
      bodyMedium: _sans(15, height: 1.5).copyWith(color: ink),
      bodySmall: _sans(13, height: 1.45).copyWith(color: muted),
      labelLarge: _sans(15, weight: FontWeight.w600, spacing: 0.1).copyWith(color: ink),
      labelMedium: _sans(13, weight: FontWeight.w600, spacing: 0.2).copyWith(color: ink),
      labelSmall: _sans(11, weight: FontWeight.w600, spacing: 1.2).copyWith(color: muted),
    );

/// Semantic colours and extras not covered by [ColorScheme].
@immutable
class ChefiiPalette extends ThemeExtension<ChefiiPalette> {
  const ChefiiPalette({
    required this.background,
    required this.surface,
    required this.surfaceSoft,
    required this.ink,
    required this.muted,
    required this.hairline,
    required this.accent,
    required this.accentSoft,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.error,
    required this.errorSoft,
    required this.info,
    required this.infoSoft,
  });

  final Color background, surface, surfaceSoft, ink, muted, hairline, accent, accentSoft;
  final Color success, successSoft, warning, warningSoft, error, errorSoft, info, infoSoft;

  static const light = ChefiiPalette(
    background: ChefiiColors.porcelain,
    surface: ChefiiColors.ivory,
    surfaceSoft: ChefiiColors.sageSoft,
    ink: ChefiiColors.ink,
    muted: ChefiiColors.muted,
    hairline: ChefiiColors.hairline,
    accent: ChefiiColors.champagne,
    accentSoft: ChefiiColors.champagneSoft,
    success: ChefiiColors.success,
    successSoft: ChefiiColors.successSoft,
    warning: ChefiiColors.warning,
    warningSoft: ChefiiColors.warningSoft,
    error: ChefiiColors.error,
    errorSoft: ChefiiColors.errorSoft,
    info: ChefiiColors.info,
    infoSoft: ChefiiColors.infoSoft,
  );

  static const dark = ChefiiPalette(
    background: ChefiiColors.darkBackground,
    surface: ChefiiColors.darkSurface,
    surfaceSoft: ChefiiColors.darkSurfaceHigh,
    ink: ChefiiColors.darkInk,
    muted: ChefiiColors.darkMuted,
    hairline: ChefiiColors.darkHairline,
    accent: Color(0xFFCDB58E),
    accentSoft: Color(0xFF3A3326),
    success: Color(0xFF8FC9A3),
    successSoft: Color(0xFF203629),
    warning: Color(0xFFE2B865),
    warningSoft: Color(0xFF3B301B),
    error: Color(0xFFEE9A90),
    errorSoft: Color(0xFF41231F),
    info: Color(0xFF9DBCD4),
    infoSoft: Color(0xFF1F2E3A),
  );

  @override
  ChefiiPalette copyWith() => this;

  @override
  ChefiiPalette lerp(ChefiiPalette? other, double t) => t < 0.5 || other == null ? this : other;
}

extension ChefiiThemeX on BuildContext {
  ChefiiPalette get palette => Theme.of(this).extension<ChefiiPalette>() ?? ChefiiPalette.light;
  TextTheme get text => Theme.of(this).textTheme;
  ColorScheme get colors => Theme.of(this).colorScheme;
  bool get reduceMotion => MediaQuery.maybeDisableAnimationsOf(this) ?? false;
}

ThemeData _build({
  required Brightness brightness,
  required ChefiiPalette p,
  required Color primary,
  required Color onPrimary,
}) {
  final scheme = ColorScheme(
    brightness: brightness,
    primary: primary,
    onPrimary: onPrimary,
    primaryContainer: p.surfaceSoft,
    onPrimaryContainer: p.ink,
    secondary: p.accent,
    onSecondary: brightness == Brightness.light ? ChefiiColors.ink : ChefiiColors.darkBackground,
    secondaryContainer: p.accentSoft,
    onSecondaryContainer: p.ink,
    tertiary: p.info,
    onTertiary: Colors.white,
    error: p.error,
    onError: Colors.white,
    errorContainer: p.errorSoft,
    onErrorContainer: p.error,
    surface: p.surface,
    onSurface: p.ink,
    onSurfaceVariant: p.muted,
    surfaceContainerLowest: p.surface,
    surfaceContainerLow: p.background,
    surfaceContainer: p.surface,
    surfaceContainerHigh: p.surfaceSoft,
    surfaceContainerHighest: p.surfaceSoft,
    outline: p.hairline,
    outlineVariant: p.hairline,
    shadow: Colors.black,
    inverseSurface: p.ink,
    onInverseSurface: p.surface,
  );
  final text = _textTheme(p.ink, p.muted);
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.m));

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.background,
    canvasColor: p.background,
    fontFamily: 'Inter',
    textTheme: text,
    extensions: [p],
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      foregroundColor: p.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: text.titleMedium,
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.l),
        side: BorderSide(color: p.hairline),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        disabledBackgroundColor: p.hairline,
        disabledForegroundColor: p.muted,
        minimumSize: const Size(kMinTouchTarget, 56),
        padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
        shape: shape,
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        minimumSize: const Size(kMinTouchTarget, 56),
        padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
        side: BorderSide(color: p.hairline, width: 1.2),
        shape: shape,
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primary,
        minimumSize: const Size(kMinTouchTarget, kMinTouchTarget),
        textStyle: text.labelLarge,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(kMinTouchTarget, kMinTouchTarget), foregroundColor: p.ink),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.m),
      labelStyle: text.bodyMedium?.copyWith(color: p.muted),
      hintStyle: text.bodyMedium?.copyWith(color: p.muted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.m), borderSide: BorderSide(color: p.hairline)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.m), borderSide: BorderSide(color: p.hairline)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.m), borderSide: BorderSide(color: primary, width: 1.6)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.m), borderSide: BorderSide(color: p.error)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.surface,
      selectedColor: p.surfaceSoft,
      side: BorderSide(color: p.hairline),
      labelStyle: text.labelMedium,
      padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.xs),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xl)),
      checkmarkColor: primary,
      showCheckmark: true,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: p.surfaceSoft,
      elevation: 0,
      height: 72,
      labelTextStyle: WidgetStatePropertyAll(text.labelMedium),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? primary : p.muted, size: 24),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: p.hairline,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.l)),
      titleTextStyle: text.headlineSmall,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.ink,
      contentTextStyle: text.bodyMedium?.copyWith(color: p.surface),
      actionTextColor: brightness == Brightness.light ? ChefiiColors.sage : ChefiiColors.forest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.m)),
    ),
    dividerTheme: DividerThemeData(color: p.hairline, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.m),
      minVerticalPadding: Space.s,
      iconColor: p.muted,
      titleTextStyle: text.bodyLarge,
      subtitleTextStyle: text.bodySmall,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? onPrimary : p.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? primary : p.hairline),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: primary, linearTrackColor: p.hairline, circularTrackColor: p.hairline),
    sliderTheme: SliderThemeData(activeTrackColor: primary, thumbColor: primary, inactiveTrackColor: p.hairline),
  );
}

abstract final class ChefiiTheme {
  static final light = _build(
    brightness: Brightness.light,
    p: ChefiiPalette.light,
    primary: ChefiiColors.forest,
    onPrimary: ChefiiColors.ivory,
  );

  static final dark = _build(
    brightness: Brightness.dark,
    p: ChefiiPalette.dark,
    primary: ChefiiColors.darkPrimary,
    onPrimary: ChefiiColors.darkBackground,
  );
}
