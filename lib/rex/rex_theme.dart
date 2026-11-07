import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

abstract final class RexColors {
  static const background = Color(0xFF302638);
  static const card = Color(0xFF51435E);
  static const text = Color(0xFFFDFBFF);
  static const muted = Color(0xFFBDB3C6);
  static const purple = Color(0xFFB792F2);
}

ThemeData buildRexTheme() => ThemeData(
  brightness: Brightness.dark,
  useMaterial3: true,
  scaffoldBackgroundColor: RexColors.background,
  fontFamilyFallback: const ['PingFang SC', 'Noto Sans SC'],
  colorScheme: const ColorScheme.dark(
    primary: RexColors.purple,
    surface: RexColors.background,
    onSurface: RexColors.text,
  ),
  splashFactory: NoSplash.splashFactory,
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.transparent,
    foregroundColor: Colors.white,
    centerTitle: true,
    scrolledUnderElevation: 0,
  ),
  cupertinoOverrideTheme: const CupertinoThemeData(
    brightness: Brightness.dark,
    primaryColor: RexColors.purple,
  ),
  pageTransitionsTheme: const PageTransitionsTheme(
    builders: {
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
    },
  ),
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: RexColors.card,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
  ),
);
