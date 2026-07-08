/// Numeric and visual constants shared across the design system.
///
/// Centralizes spacing, corner radii, and motion durations so widgets stay
/// consistent and theme tweaks happen in one place. Mirrors the role of
/// `res/values/dimens_overdrive.xml` in the original Android app.
class AppDimensions {
  AppDimensions._();

  // Spacing scale (4dp grid)
  static const double space3 = 3.0;
  static const double space4 = 4.0;
  static const double space8 = 8.0;
  static const double space12 = 12.0;
  static const double space16 = 16.0;
  static const double space20 = 20.0;
  static const double space24 = 24.0;
  static const double space32 = 32.0;
  static const double space40 = 40.0;
  static const double space48 = 48.0;

  // Corner radii
  static const double radius4 = 4.0;
  static const double radius8 = 8.0;
  static const double radius12 = 12.0;
  static const double radius16 = 16.0;
  static const double radius24 = 24.0;
  static const double radiusFull = 9999.0;

  // Motion durations
  static const Duration durationShort = Duration(milliseconds: 150);
  static const Duration durationMedium = Duration(milliseconds: 300);
  static const Duration durationLong = Duration(milliseconds: 450);

  // Layout breakpoints
  static const double compactBreakpoint = 600; // phone vs tablet
  static const double mediumBreakpoint = 840; // tablet vs desktop

  // Elevation tokens
  static const double elevationLow = 1.0;
  static const double elevationMedium = 3.0;
  static const double elevationHigh = 6.0;
}
