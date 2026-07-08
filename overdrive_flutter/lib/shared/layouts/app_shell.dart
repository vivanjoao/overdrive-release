import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../routing/routes.dart';
import '../../theme/dimensions.dart';
import '../../l10n/generated/app_localizations.dart';

/// Root scaffold hosting the adaptive navigation chrome and the active
/// branch's content.
///
/// Layout strategy:
///  * width  ≥ [AppDimensions.compactBreakpoint] → [NavigationRail] (left)
///  * width  <  [AppDimensions.compactBreakpoint] → [Scaffold.drawer] + AppBar
///
/// Branch state and content are owned by the supplied [navigationShell]
/// (a [StatefulNavigationShell] produced by [StatefulShellRoute.indexedStack]),
/// so each top-level destination keeps its own back stack and scroll position
/// when the user switches tabs.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= AppDimensions.compactBreakpoint;

    if (wide) {
      return _WideShell(navigationShell: navigationShell);
    }
    return _CompactShell(navigationShell: navigationShell);
  }

  /// Switches the active branch and (for the wide rail) restores focus.
  static void goToBranch(
    BuildContext context,
    StatefulNavigationShell shell,
    int index,
  ) {
    shell.goBranch(
      index,
      initialLocation: index == shell.currentIndex,
    );
  }
}

/// Brand header shown at the top of the rail and inside the drawer.
class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.compact});

  /// When true, lays out horizontally (rail uses a vertical logo block).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? AppDimensions.space16 : AppDimensions.space12,
        AppDimensions.space16,
        compact ? AppDimensions.space16 : AppDimensions.space12,
        AppDimensions.space8,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppDimensions.radius8),
            ),
            child: Icon(
              Icons.safety_check_rounded,
              color: theme.colorScheme.onPrimaryContainer,
              size: 20,
            ),
          ),
          if (compact) ...[
            const SizedBox(width: AppDimensions.space12),
            Text(
              AppConfig.appName,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Wide layout: extended [NavigationRail] on the left, content fills the rest.
class _WideShell extends StatelessWidget {
  const _WideShell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context);
    return Scaffold(
      body: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: Column(
              children: [
                const _BrandHeader(compact: true),
                Expanded(
                  child: NavigationRail(
                    extended: true,
                    minWidth: 220,
                    groupAlignment: 0,
                    selectedIndex: navigationShell.currentIndex,
                    onDestinationSelected: (i) => AppShell.goToBranch(
                        context, navigationShell, i),
                    destinations: [
                      for (final d in AppDestinations.all)
                        NavigationRailDestination(
                          icon: Icon(d.icon),
                          selectedIcon: Icon(d.selectedIcon),
                          label: Text(_labelFor(loc, d)),
                        ),
                    ],
                  ),
                ),
                const _VersionFooter(),
              ],
            ),
          ),
          Expanded(child: navigationShell),
        ],
      ),
    );
  }
}

/// Narrow layout: hamburger drawer triggered from the AppBar.
class _CompactShell extends StatelessWidget {
  const _CompactShell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context);
    final current = AppDestinations
        .all[navigationShell.currentIndex.clamp(0, AppDestinations.all.length - 1)];

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Text(_labelFor(loc, current)),
      ),
      drawer: Drawer(
        child: Column(
          children: [
            const _BrandHeader(compact: true),
            Divider(
                color: theme.colorScheme.outlineVariant,
                height: 1,
                indent: AppDimensions.space16,
                endIndent: AppDimensions.space16),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                    vertical: AppDimensions.space8),
                children: [
                  for (var i = 0; i < AppDestinations.all.length; i++)
                    _DrawerTile(
                      destination: AppDestinations.all[i],
                      selected: i == navigationShell.currentIndex,
                      onTap: () {
                        Navigator.of(context).pop();
                        AppShell.goToBranch(context, navigationShell, i);
                      },
                    ),
                ],
              ),
            ),
            const _VersionFooter(),
          ],
        ),
      ),
      body: navigationShell,
    );
  }
}

class _DrawerTile extends StatelessWidget {
  const _DrawerTile({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final AppDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.space12, vertical: AppDimensions.space3),
      child: Material(
        color: selected
            ? theme.colorScheme.secondaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppDimensions.space16,
                vertical: AppDimensions.space12),
            child: Row(
              children: [
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  color: selected
                      ? theme.colorScheme.onSecondaryContainer
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppDimensions.space16),
                Expanded(
                  child: Text(
                    _labelFor(loc, destination),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: selected
                          ? theme.colorScheme.onSecondaryContainer
                          : theme.colorScheme.onSurface,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VersionFooter extends StatelessWidget {
  const _VersionFooter();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.space16, vertical: AppDimensions.space8),
        child: Text(
          'v${AppConfig.appVersion}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontFamily: 'JetBrains Mono',
          ),
        ),
      ),
    );
  }
}

/// Maps a destination's [AppDestination.labelKey] to a localized string.
///
/// Uses a `switch` so the compiler enforces that every destination has a
/// translation — if a new destination is added without a case, this becomes
/// a compile error rather than a missing-string at runtime.
String _labelFor(AppLocalizations loc, AppDestination destination) {
  switch (destination.labelKey) {
    case 'dashboard':
      return loc.navDashboard;
    case 'liveView':
      return loc.navLiveView;
    case 'surveillance':
      return loc.navSurveillance;
    case 'recordings':
      return loc.navRecordings;
    case 'vehicleControl':
      return loc.navVehicleControl;
    case 'trips':
      return loc.navTrips;
    case 'settings':
      return loc.navSettings;
      default:
      // Only reachable if a destination was added without updating this map.
      throw ArgumentError(
          'Missing localization case for labelKey: ${destination.labelKey}');
  }
}
