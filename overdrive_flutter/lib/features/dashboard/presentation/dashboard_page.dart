import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/result/result.dart';
import '../../../routing/routes.dart';
import '../../../services/backend_service.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/coming_soon.dart';
import '../../../shared/widgets/status_chip.dart';
import '../../../theme/dimensions.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'providers/connection_status_provider.dart';

/// Top-level landing page shown when the app opens.
///
/// Hosts the brand hero, a quick-access grid to other destinations, and a
/// live status panel that reflects the current head-unit connection.
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: Text(loc.dashboardTitle),
            pinned: true,
            stretch: true,
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
                AppDimensions.space16,
                AppDimensions.space8,
                AppDimensions.space16,
                AppDimensions.space32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const _HeroCard(),
                const SizedBox(height: AppDimensions.space24),
                const SectionHeader(title: 'Connection'),
                const SizedBox(height: AppDimensions.space8),
                const _ConnectionCard(),
                const SizedBox(height: AppDimensions.space24),
                const SectionHeader(title: 'Quick access'),
                const SizedBox(height: AppDimensions.space8),
                const _QuickAccessGrid(),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppDimensions.radius16),
            ),
            child: Icon(
              Icons.safety_check_rounded,
              size: 32,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: AppDimensions.space16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome to OverDrive',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppDimensions.space4),
                Text(
                  'Remote client for your BYD vehicle. Connect to the head '
                  'unit on your car to view live cameras, browse recordings, '
                  'and control your vehicle.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionCard extends ConsumerWidget {
  const _ConnectionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(connectionStatusProvider);

    return AppCard(
      child: statusAsync.when(
        data: (status) => _StatusContent(status: status),
        loading: () => const _StatusContent(status: Connecting(null)),
        error: (e, _) =>
            _StatusContent(status: Offline(UnexpectedError('$e'))),
      ),
    );
  }
}

class _StatusContent extends StatelessWidget {
  const _StatusContent({required this.status});

  final ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (status) {
      case Disconnected():
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const StatusChip(
              icon: Icons.cloud_off_rounded,
              label: 'Head unit connection',
              value: 'Not configured',
              severity: StatusSeverity.idle,
            ),
            const SizedBox(height: AppDimensions.space12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () =>
                    context.go('${AppDestinations.settings.path}/connection'),
                icon: const Icon(Icons.add_link_rounded),
                label: const Text('Connect to car'),
              ),
            ),
          ],
        );
      case Connecting(:final previous):
        final label = switch (previous) {
          Online() => 'Reconnecting…',
          Offline() => 'Retrying…',
          _ => 'Connecting…',
        };
        return Column(
          children: [
            StatusChip(
              icon: Icons.sync_rounded,
              label: 'Head unit connection',
              value: label,
              severity: StatusSeverity.info,
            ),
            if (previous is Online)
              _HealthRows(summary: previous.summary, dimmed: true),
          ],
        );
      case Online(:final summary):
        return Column(
          children: [
            const StatusChip(
              icon: Icons.cloud_done_rounded,
              label: 'Head unit connection',
              value: 'Online',
              severity: StatusSeverity.success,
            ),
            _HealthRows(summary: summary, dimmed: false),
          ],
        );
      case Offline(:final error):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const StatusChip(
              icon: Icons.error_outline_rounded,
              label: 'Head unit connection',
              value: 'Offline',
              severity: StatusSeverity.danger,
            ),
            const SizedBox(height: AppDimensions.space8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppDimensions.space12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
                borderRadius:
                    BorderRadius.circular(AppDimensions.radius8),
              ),
              child: Text(
                error.message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
            ),
            const SizedBox(height: AppDimensions.space12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => context
                    .go('${AppDestinations.settings.path}/connection'),
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('Connection settings'),
              ),
            ),
          ],
        );
    }
  }
}

class _HealthRows extends StatelessWidget {
  const _HealthRows({required this.summary, required this.dimmed});

  final HealthSummary summary;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: dimmed ? 0.5 : 1.0,
      child: Column(
        children: [
          Divider(
            height: AppDimensions.space16,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          StatusChip(
            icon: Icons.memory_outlined,
            label: 'Daemon',
            value: summary.daemonRunning ? 'Running' : 'Idle',
            severity: summary.daemonRunning
                ? StatusSeverity.success
                : StatusSeverity.idle,
          ),
          StatusChip(
            icon: Icons.shield_moon_outlined,
            label: 'Sentry mode',
            value: summary.sentryArmed ? 'Armed' : 'Disarmed',
            severity: summary.sentryArmed
                ? StatusSeverity.warning
                : StatusSeverity.idle,
          ),
          if (summary.version != null)
            StatusChip(
              icon: Icons.tag_rounded,
              label: 'Head unit version',
              value: summary.version!,
              severity: StatusSeverity.idle,
            ),
        ],
      ),
    );
  }
}

class _QuickAccessGrid extends StatelessWidget {
  const _QuickAccessGrid();

  @override
  Widget build(BuildContext context) {
    final tiles = AppDestinations.all
        .where((d) => d.name != AppDestinations.dashboard.name)
        .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 180).floor().clamp(2, 4);
        const spacing = AppDimensions.space12;
        final tileWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final d in tiles)
              SizedBox(
                width: tileWidth,
                child: _QuickAccessTile(destination: d),
              ),
          ],
        );
      },
    );
  }
}

class _QuickAccessTile extends StatelessWidget {
  const _QuickAccessTile({required this.destination});

  final AppDestination destination;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context);
    return AppCard(
      onTap: () => context.go(destination.path),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppDimensions.radius12),
            ),
            child: Icon(
              destination.icon,
              size: 22,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: AppDimensions.space12),
          Text(
            _labelFor(loc, destination),
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

String _labelFor(AppLocalizations loc, AppDestination destination) {
  switch (destination.labelKey) {
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
      return destination.name;
  }
}
