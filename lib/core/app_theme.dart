import 'package:flutter/material.dart';

abstract final class CinemaColors {
  static const background = Color(0xFFF3F0EC);
  static const elevated = Color(0xFFFCFAF7);
  static const elevatedHigh = Color(0xFFE9E2DB);
  static const text = Color(0xFF292320);
  static const muted = Color(0xFF74665D);
  static const faint = Color(0xFF887A70);
  static const accent = Color(0xFF765440);
  static const border = Color(0xFFDCCFC4);
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
    brightness: Brightness.light,
    useMaterial3: true,
    scaffoldBackgroundColor: CinemaColors.background,
    colorScheme: const ColorScheme.light(
      primary: CinemaColors.accent,
      secondary: CinemaColors.accent,
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
      activeTrackColor: CinemaColors.accent,
      inactiveTrackColor: const Color(0x55FFFFFF),
      thumbColor: CinemaColors.accent,
      overlayColor: CinemaColors.accent.withValues(alpha: 0.16),
      trackHeight: 3,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: CinemaColors.accent,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: CinemaColors.text,
        side: const BorderSide(color: CinemaColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
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
