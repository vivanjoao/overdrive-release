import 'package:flutter/material.dart';

/// Brand palette and Material 3 token colors.
///
/// These values are ported verbatim from the original Android app's
/// `res/values/colors_m3.xml` (and its `values-night/` override) so the
/// Flutter client shares the exact look of the head-unit APK.
///
/// Seed color used by the original Material Theme Builder: `#00D4AA`.
///
/// Status colors (`success` / `warning` / `danger` / `info`) are brand-aware
/// and live alongside the M3 system tokens so feature code can reference
/// them without picking light/dark variants manually.
@immutable
class AppColors {
  const AppColors._();

  // ── Brand seed ──────────────────────────────────────────────────────────
  static const Color seed = Color(0xFF00D4AA);
  static const Color brandGreen = Color(0xFF00876C);

  // ── Light Material 3 system tokens ──────────────────────────────────────
  static const ColorScheme lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF00876C),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFF78F3CC),
    onPrimaryContainer: Color(0xFF002115),
    secondary: Color(0xFF4B635A),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFCDE8DC),
    onSecondaryContainer: Color(0xFF072019),
    tertiary: Color(0xFF00658F),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFC5E7FF),
    onTertiaryContainer: Color(0xFF001E2E),
    error: Color(0xFFBA1A1A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    surface: Color(0xFFF7FAF7),
    onSurface: Color(0xFF181C1A),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF1F4F0),
    surfaceContainer: Color(0xFFECEFEC),
    surfaceContainerHigh: Color(0xFFE6E9E6),
    surfaceContainerHighest: Color(0xFFE0E4E1),
    surfaceDim: Color(0xFFD8DBD7),
    surfaceBright: Color(0xFFF7FAF7),
    onSurfaceVariant: Color(0xFF3F4944),
    outline: Color(0xFF6F7975),
    outlineVariant: Color(0xFFBFC9C3),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF2D3130),
    onInverseSurface: Color(0xFFEEF1ED),
    inversePrimary: Color(0xFF5DDBB6),
  );

  // ── Dark Material 3 system tokens ───────────────────────────────────────
  static const ColorScheme darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF5DDBB6),
    onPrimary: Color(0xFF003828),
    primaryContainer: Color(0xFF00513B),
    onPrimaryContainer: Color(0xFF78F3CC),
    secondary: Color(0xFFB1CCC0),
    onSecondary: Color(0xFF1D352D),
    secondaryContainer: Color(0xFF334B43),
    onSecondaryContainer: Color(0xFFCDE8DC),
    tertiary: Color(0xFF85CFFF),
    onTertiary: Color(0xFF00344C),
    tertiaryContainer: Color(0xFF004C6C),
    onTertiaryContainer: Color(0xFFC5E7FF),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Color(0xFF0E1311),
    onSurface: Color(0xFFDEE4E0),
    surfaceContainerLowest: Color(0xFF080D0B),
    surfaceContainerLow: Color(0xFF161B19),
    surfaceContainer: Color(0xFF1A1F1D),
    surfaceContainerHigh: Color(0xFF242927),
    surfaceContainerHighest: Color(0xFF2F3432),
    surfaceDim: Color(0xFF0E1311),
    surfaceBright: Color(0xFF343937),
    onSurfaceVariant: Color(0xFFBFC9C3),
    outline: Color(0xFF899692),
    outlineVariant: Color(0xFF3F4944),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFDEE4E0),
    onInverseSurface: Color(0xFF2D3130),
    inversePrimary: Color(0xFF00876C),
  );
}

/// Brand-aligned semantic status colors, brightness-aware.
///
/// Use these for state indicators (recording dot, sentry armed, battery low)
/// instead of raw `Colors.green` / `Colors.red`.
@immutable
class StatusColors {
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;

  const StatusColors({
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
  });

  static const StatusColors light = StatusColors(
    success: Color(0xFF1F7A3F),
    warning: Color(0xFFA6601C),
    danger: Color(0xFFBA1A1A),
    info: Color(0xFF00658F),
  );

  static const StatusColors dark = StatusColors(
    success: Color(0xFF5BD382),
    warning: Color(0xFFFFB870),
    danger: Color(0xFFFFB4AB),
    info: Color(0xFF85CFFF),
  );

  static StatusColors of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}
