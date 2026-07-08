import 'package:flutter/material.dart';

import 'colors.dart';
import 'dimensions.dart';

/// Builds the light and dark [ThemeData] for the app.
///
/// Both themes are constructed from the exact Material 3 token palette used
/// by the head-unit APK (see [AppColors]) so the two clients look identical.
/// Component themes (Card, AppBar, NavigationRail, FilledButton, …) are
/// customized here once so feature widgets stay declarative.
class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(AppColors.lightScheme);
  static ThemeData dark() => _build(AppColors.darkScheme);

  static ThemeData _build(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,

      // ── AppBar ───────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: AppDimensions.elevationLow,
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surfaceTint,
        foregroundColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
      ),

      // ── Cards ────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radius16),
        ),
        margin: EdgeInsets.zero,
      ),

      // ── Buttons ──────────────────────────────────────────────────────
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.space24, vertical: AppDimensions.space12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
          ),
        ),
      ),

      // ── Inputs ───────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radius12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.space16, vertical: AppDimensions.space12),
      ),

      // ── Navigation ───────────────────────────────────────────────────
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.secondaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
            size: 24,
          );
        }),
      ),

      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.secondaryContainer,
        selectedIconTheme:
            IconThemeData(color: scheme.onSecondaryContainer, size: 26),
        unselectedIconTheme:
            IconThemeData(color: scheme.onSurfaceVariant, size: 24),
        selectedLabelTextStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),

      drawerTheme: DrawerThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        scrimColor: scheme.scrim.withValues(alpha: 0.5),
      ),

      // ── Dividers ─────────────────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),

      // ── SnackBars ────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radius12),
        ),
      ),

      // ── Dialogs ──────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radius24),
        ),
      ),

      // ── Chip ─────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        selectedColor: scheme.secondaryContainer,
        checkmarkColor: scheme.onSecondaryContainer,
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radius8),
        ),
      ),

      // ── Misc ─────────────────────────────────────────────────────────
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radius12),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        elevation: AppDimensions.elevationMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radius16),
        ),
      ),
    );
  }
}

/// Inherited widget so any descendant can grab the [StatusColors] without
/// having to branch on brightness.
extension StatusColorsBuildContext on BuildContext {
  StatusColors get statusColors =>
      StatusColors.of(Theme.of(this).brightness);
}
