import 'package:flutter/material.dart';

abstract final class CinemaColors {
  static const background = Color(0xFF07080B);
  static const elevated = Color(0xFF11141A);
  static const elevatedHigh = Color(0xFF181C24);
  static const text = Color(0xFFF4F5F7);
  static const muted = Color(0xFFA4AAB6);
  static const faint = Color(0xFF8C94A3);
  static const red = Color(0xFFE50914);
  static const border = Color(0xFF272C36);
}

ThemeData buildCinemaTheme() {
  const fallback = <String>[
    'PingFang SC',
    'Microsoft YaHei',
    'Noto Sans SC',
    'Noto Sans CJK SC',
    'sans-serif',
  ];
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: CinemaColors.background,
    colorScheme: const ColorScheme.dark(
      primary: CinemaColors.red,
      secondary: CinemaColors.red,
      surface: CinemaColors.elevated,
      onPrimary: Colors.white,
      onSurface: CinemaColors.text,
      outline: CinemaColors.border,
    ),
    splashFactory: InkSparkle.splashFactory,
  );
  TextTheme textTheme = base.textTheme
      .apply(
        bodyColor: CinemaColors.text,
        displayColor: CinemaColors.text,
        fontFamilyFallback: fallback,
      )
      .copyWith(
        displayLarge: base.textTheme.displayLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
          fontFamilyFallback: fallback,
        ),
        headlineLarge: base.textTheme.headlineLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          fontFamilyFallback: fallback,
        ),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          fontFamilyFallback: fallback,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          fontFamilyFallback: fallback,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          fontFamilyFallback: fallback,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          fontFamilyFallback: fallback,
          height: 1.45,
        ),
        bodySmall: base.textTheme.bodySmall?.copyWith(
          color: CinemaColors.muted,
          fontFamilyFallback: fallback,
        ),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          fontFamilyFallback: fallback,
        ),
      );
  return base.copyWith(
    textTheme: textTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: CinemaColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    dividerTheme: const DividerThemeData(color: CinemaColors.border, space: 1),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: CinemaColors.red,
      inactiveTrackColor: const Color(0x55FFFFFF),
      thumbColor: CinemaColors.red,
      overlayColor: CinemaColors.red.withValues(alpha: 0.16),
      trackHeight: 3,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: CinemaColors.red,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: CinemaColors.text,
        side: const BorderSide(color: CinemaColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: CinemaColors.elevatedHigh,
      contentTextStyle: TextStyle(color: CinemaColors.text),
      behavior: SnackBarBehavior.floating,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: CinemaColors.elevated,
      modalBackgroundColor: CinemaColors.elevated,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: CinemaColors.elevated,
      surfaceTintColor: Colors.transparent,
    ),
  );
}
