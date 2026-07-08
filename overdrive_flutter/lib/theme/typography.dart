import 'package:flutter/material.dart';

/// Font family names used across the app.
///
/// The original Android app pairs `Inter` (UI) with `JetBrains Mono`
/// (telemetry / logs / ADB output). We expose them as named tokens so a
/// feature page never hard-codes a font family; swapping fonts later
/// (e.g. bundling via `pubspec.yaml` instead of Google Fonts) is a one-line
/// change here.
class AppTypography {
  AppTypography._();

  static const String display = 'Inter';
  static const String mono = 'JetBrains Mono';

  /// Text theme built on top of the framework defaults.
  ///
  /// We let Material 3 seed the sizes/weights so we stay consistent with the
  /// system display scaling, and only override the font family. When bundled
  /// font assets are added in a later module, plug them in here.
  static TextTheme base(BuildContext context) {
    final base = Theme.of(context).textTheme;
    return base;
  }
}
