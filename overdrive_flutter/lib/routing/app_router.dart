import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/dashboard/presentation/dashboard_page.dart';
import '../features/live_view/presentation/live_view_page.dart';
import '../features/recordings/presentation/recording_player_page.dart';
import '../features/recordings/presentation/recordings_page.dart';
import '../features/settings/presentation/connection_settings_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/surveillance/presentation/surveillance_page.dart';
import '../features/trips/presentation/trips_page.dart';
import '../features/vehicle/presentation/vehicle_page.dart';
import '../shared/layouts/app_shell.dart';
import 'routes.dart';

/// Provider exposing the configured [GoRouter].
///
/// Kept as a provider (rather than a top-level constant) so future modules
/// can react to auth state changes by invalidating the router — e.g. redirect
/// to a PIN lock screen or onboarding flow before reaching the shell.
final goRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppDestinations.initial,
    debugLogDiagnostics: true,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                name: AppDestinations.dashboard.name,
                path: AppDestinations.dashboard.path,
                builder: (context, state) => const DashboardPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                name: AppDestinations.liveView.name,
                path: AppDestinations.liveView.path,
                builder: (context, state) => const LiveViewPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                name: AppDestinations.surveillance.name,
                path: AppDestinations.surveillance.path,
                builder: (context, state) => const SurveillancePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                name: AppDestinations.recordings.name,
                path: AppDestinations.recordings.path,
                builder: (context, state) => const RecordingsPage(),
                routes: [
                  GoRoute(
                    name: 'recordingPlayer',
                    path: 'player',
                    builder: (context, state) {
                      final params = state.extra as PlayerParams?;
                      if (params == null) {
                        return const RecordingsPage();
                      }
                      return RecordingPlayerPage(params: params);
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                name: AppDestinations.vehicle.name,
                path: AppDestinations.vehicle.path,
                builder: (context, state) => const VehiclePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                name: AppDestinations.trips.name,
                path: AppDestinations.trips.path,
                builder: (context, state) => const TripsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                name: AppDestinations.settings.name,
                path: AppDestinations.settings.path,
                builder: (context, state) => const SettingsPage(),
                routes: [
                  GoRoute(
                    name: 'connectionSettings',
                    path: 'connection',
                    builder: (context, state) =>
                        const ConnectionSettingsPage(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => _RouteErrorView(error: state.error),
  );
});

/// Fallback view shown for unroutable locations.
class _RouteErrorView extends StatelessWidget {
  const _RouteErrorView({required this.error});

  final Exception? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Page not found')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.explore_off_outlined,
                  size: 64, color: theme.colorScheme.outline),
              const SizedBox(height: 16),
              Text('This route does not exist.',
                  style: theme.textTheme.titleMedium),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text('$error',
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center),
              ],
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: () =>
                    GoRouter.of(context).go(AppDestinations.initial),
                child: const Text('Back to Dashboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
