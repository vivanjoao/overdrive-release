import 'package:flutter/material.dart';

/// Declarative catalog of top-level navigation destinations.
///
/// A single source of truth that drives both the navigation rail (wide) and
/// the drawer (narrow), the go_router branch list, and deep-link resolution.
/// Adding a new top-level feature is therefore a one-line change here, plus
/// a route entry in [AppRouter].
@immutable
class AppDestination {
  final String path;
  final String labelKey;
  final IconData selectedIcon;
  final IconData icon;
  final String name;

  const AppDestination({
    required this.path,
    required this.labelKey,
    required this.selectedIcon,
    required this.icon,
    required this.name,
  });

  /// Localization key suffix — combined with the `nav` prefix at call sites
  /// (e.g. `labelKey = 'dashboard'` → `AppLocalizations.navDashboard`).
}

/// All top-level destinations, in the order they should appear.
///
/// Mirrors the sidebar of the original Android app:
/// Dashboard → Live View → Surveillance → Recordings →
/// Vehicle Control → Trips → Settings.
class AppDestinations {
  AppDestinations._();

  static const dashboard = AppDestination(
    name: 'dashboard',
    path: '/dashboard',
    labelKey: 'dashboard',
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard_rounded,
  );

  static const liveView = AppDestination(
    name: 'liveView',
    path: '/live-view',
    labelKey: 'liveView',
    icon: Icons.videocam_outlined,
    selectedIcon: Icons.videocam_rounded,
  );

  static const surveillance = AppDestination(
    name: 'surveillance',
    path: '/surveillance',
    labelKey: 'surveillance',
    icon: Icons.shield_outlined,
    selectedIcon: Icons.shield_rounded,
  );

  static const recordings = AppDestination(
    name: 'recordings',
    path: '/recordings',
    labelKey: 'recordings',
    icon: Icons.video_library_outlined,
    selectedIcon: Icons.video_library_rounded,
  );

  static const vehicle = AppDestination(
    name: 'vehicle',
    path: '/vehicle',
    labelKey: 'vehicleControl',
    icon: Icons.directions_car_outlined,
    selectedIcon: Icons.directions_car_rounded,
  );

  static const trips = AppDestination(
    name: 'trips',
    path: '/trips',
    labelKey: 'trips',
    icon: Icons.route_outlined,
    selectedIcon: Icons.route_rounded,
  );

  static const settings = AppDestination(
    name: 'settings',
    path: '/settings',
    labelKey: 'settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
  );

  /// Ordered list rendered by the shell.
  static const List<AppDestination> all = [
    dashboard,
    liveView,
    surveillance,
    recordings,
    vehicle,
    trips,
    settings,
  ];

  /// Initial route used when the app launches with no deep link.
  /// Inlined as a string literal so it can be used in other `const` contexts
  /// (Dart's const evaluator cannot resolve field access on a const instance).
  static const String initial = '/dashboard';

  /// Looks up the destination whose [path] matches, or null.
  static AppDestination? byPath(String path) {
    for (final d in all) {
      if (d.path == path) return d;
    }
    return null;
  }
}
