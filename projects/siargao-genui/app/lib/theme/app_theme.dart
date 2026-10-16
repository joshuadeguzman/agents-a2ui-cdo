import 'package:flutter/material.dart';

/// Bundled font family (static instances of Google Sans Flex, OFL).
const String appFontFamily = 'GoogleSansFlex';

/// Fixed palette tuned for a projector: high contrast ink on white with one
/// calm ocean teal accent.
abstract final class AppColors {
  /// Primary accent, ocean teal.
  static const Color teal = Color(0xFF00676E);

  /// Light tint of the accent for containers.
  static const Color tealSoft = Color(0xFFD5EEF0);

  /// Text on [tealSoft].
  static const Color tealInk = Color(0xFF00363A);

  /// Main text color.
  static const Color ink = Color(0xFF1A1C1E);

  /// Secondary text color. Still above 7:1 on white.
  static const Color inkMuted = Color(0xFF4A5557);

  /// Hairlines and card borders.
  static const Color line = Color(0xFFDDE3E4);

  /// Page background.
  static const Color page = Color(0xFFF6F8F8);

  /// Card background.
  static const Color card = Color(0xFFFFFFFF);

  /// Sand tone used in placeholders and the local note.
  static const Color sand = Color(0xFFF4EBDD);

  /// Warning container.
  static const Color amberSoft = Color(0xFFFFF1CC);

  /// Text on [amberSoft].
  static const Color amberInk = Color(0xFF5C4200);

  /// Local insider container.
  static const Color coralSoft = Color(0xFFFBE9E2);

  /// Text on [coralSoft].
  static const Color coralInk = Color(0xFF6E2C14);
}

/// Spacing scale.
abstract final class Gaps {
  /// 4
  static const double xs = 4;

  /// 8
  static const double sm = 8;

  /// 12
  static const double md = 12;

  /// 16
  static const double lg = 16;

  /// 24
  static const double xl = 24;

  /// 32
  static const double xxl = 32;
}

/// Corner radii.
abstract final class Radii {
  /// Cards and images.
  static const double card = 20;

  /// Small elements.
  static const double small = 12;
}

/// Builds the light Material 3 theme used everywhere, including tests.
ThemeData buildAppTheme() {
  final ColorScheme scheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.teal,
        dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
      ).copyWith(
        primary: AppColors.teal,
        onPrimary: Colors.white,
        primaryContainer: AppColors.tealSoft,
        onPrimaryContainer: AppColors.tealInk,
        secondaryContainer: AppColors.tealSoft,
        onSecondaryContainer: AppColors.tealInk,
        surface: AppColors.card,
        onSurface: AppColors.ink,
        onSurfaceVariant: AppColors.inkMuted,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: AppColors.page,
        surfaceContainer: const Color(0xFFEFF3F3),
        surfaceContainerHigh: const Color(0xFFE8EEEE),
        surfaceContainerHighest: const Color(0xFFE1E8E8),
        outline: const Color(0xFF6F7979),
        outlineVariant: AppColors.line,
      );

  const String f = appFontFamily;
  const TextTheme text = TextTheme(
    displaySmall: TextStyle(
      fontFamily: f,
      fontSize: 40,
      height: 1.15,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.5,
    ),
    headlineLarge: TextStyle(
      fontFamily: f,
      fontSize: 34,
      height: 1.18,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.4,
    ),
    headlineMedium: TextStyle(
      fontFamily: f,
      fontSize: 28,
      height: 1.2,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
    ),
    headlineSmall: TextStyle(
      fontFamily: f,
      fontSize: 24,
      height: 1.25,
      fontWeight: FontWeight.w600,
    ),
    titleLarge: TextStyle(
      fontFamily: f,
      fontSize: 21,
      height: 1.3,
      fontWeight: FontWeight.w600,
    ),
    titleMedium: TextStyle(
      fontFamily: f,
      fontSize: 18,
      height: 1.35,
      fontWeight: FontWeight.w600,
    ),
    titleSmall: TextStyle(
      fontFamily: f,
      fontSize: 16,
      height: 1.35,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: TextStyle(
      fontFamily: f,
      fontSize: 18,
      height: 1.5,
      fontWeight: FontWeight.w400,
    ),
    bodyMedium: TextStyle(
      fontFamily: f,
      fontSize: 16,
      height: 1.5,
      fontWeight: FontWeight.w400,
    ),
    bodySmall: TextStyle(
      fontFamily: f,
      fontSize: 14,
      height: 1.45,
      fontWeight: FontWeight.w400,
    ),
    labelLarge: TextStyle(
      fontFamily: f,
      fontSize: 16,
      height: 1.25,
      fontWeight: FontWeight.w600,
    ),
    labelMedium: TextStyle(
      fontFamily: f,
      fontSize: 14,
      height: 1.25,
      fontWeight: FontWeight.w600,
    ),
    labelSmall: TextStyle(
      fontFamily: f,
      fontSize: 13,
      height: 1.25,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
    ),
  );
  final TextTheme themed = text.apply(
    bodyColor: AppColors.ink,
    displayColor: AppColors.ink,
  );

  final RoundedRectangleBorder buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
  );
  const EdgeInsets buttonPadding = EdgeInsets.symmetric(
    horizontal: 22,
    vertical: 16,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: f,
    textTheme: themed,
    scaffoldBackgroundColor: AppColors.page,
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.page,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: themed.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: const BorderSide(color: AppColors.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: buttonShape,
        padding: buttonPadding,
        textStyle: themed.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: buttonShape,
        padding: buttonPadding,
        textStyle: themed.labelLarge,
        foregroundColor: AppColors.teal,
        side: const BorderSide(color: Color(0xFF8FB3B6)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: buttonShape,
        padding: buttonPadding,
        textStyle: themed.labelLarge,
        foregroundColor: AppColors.teal,
      ),
    ),
    chipTheme: ChipThemeData(
      labelStyle: themed.labelLarge?.copyWith(fontWeight: FontWeight.w500),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: const BorderSide(color: Color(0xFFB9C6C7)),
      selectedColor: AppColors.tealSoft,
      checkmarkColor: AppColors.tealInk,
      backgroundColor: Colors.white,
    ),
    sliderTheme: const SliderThemeData(
      trackHeight: 6,
      activeTrackColor: AppColors.teal,
      thumbColor: AppColors.teal,
      inactiveTrackColor: AppColors.tealSoft,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        textStyle: themed.labelLarge,
        selectedBackgroundColor: AppColors.tealSoft,
        selectedForegroundColor: AppColors.tealInk,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: AppColors.tealSoft,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStatePropertyAll(themed.labelMedium),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: AppColors.page,
      indicatorColor: AppColors.tealSoft,
      selectedLabelTextStyle: themed.labelMedium?.copyWith(
        color: AppColors.tealInk,
      ),
      unselectedLabelTextStyle: themed.labelMedium?.copyWith(
        color: AppColors.inkMuted,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFB9C6C7)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFB9C6C7)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      contentTextStyle: themed.bodyMedium?.copyWith(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1),
  );
}
