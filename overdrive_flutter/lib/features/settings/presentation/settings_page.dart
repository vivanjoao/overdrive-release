import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/routes.dart';
import '../../../services/connection_controller.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/status_chip.dart';
import '../../../theme/dimensions.dart';
import '../../dashboard/presentation/providers/connection_status_provider.dart';

/// Settings hub.
///
/// Currently exposes only the connection group; later modules add appearance,
/// notifications, MQTT, privacy, and about sections as new cards. Each card
/// either navigates to a dedicated settings sub-page or shows inline toggles.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(connectionControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(AppDimensions.space16),
        children: [
          const _SectionTitle('Connection'),
          AppCard(
            onTap: () =>
                context.go('${AppDestinations.settings.path}/connection'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.dns_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: AppDimensions.space12),
                    Expanded(
                      child: Text(
                        config.isConfigured ? config.label : 'Head unit',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        color: Color.fromARGB(0xFF, 0x99, 0x96, 0x92)),
                  ],
                ),
                const SizedBox(height: AppDimensions.space8),
                Text(
                  config.isConfigured
                      ? config.normalizedBaseUrl
                      : 'Not configured yet — tap to add your car\'s address.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontFamily: 'JetBrains Mono',
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimensions.space24),

          const _SectionTitle('Connection status'),
          const _InlineConnectionStatus(),
          const SizedBox(height: AppDimensions.space24),

          // Placeholder groups — implemented in later modules.
          const _SectionTitle('Appearance'),
          const _PlaceholderCard(
            icon: Icons.palette_outlined,
            title: 'Theme, language',
            step: 'Module: Settings (appearance)',
          ),
          const SizedBox(height: AppDimensions.space16),
          const _SectionTitle('Notifications'),
          const _PlaceholderCard(
            icon: Icons.notifications_outlined,
            title: 'Telegram, MQTT, push',
            step: 'Modules: Telegram + MQTT',
          ),
          const SizedBox(height: AppDimensions.space16),
          const _SectionTitle('About'),
          const _PlaceholderCard(
            icon: Icons.info_outline,
            title: 'Version, licenses, privacy',
            step: 'Module: Settings (about)',
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppDimensions.space4, AppDimensions.space8, AppDimensions.space4, AppDimensions.space4),
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
          fontSize: 13,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _PlaceholderCard extends StatelessWidget {
  const _PlaceholderCard({
    required this.icon,
    required this.title,
    required this.step,
  });

  final IconData icon;
  final String title;
  final String step;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: AppDimensions.space12),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          Icon(Icons.lock_clock_outlined,
              size: 18,
              color: Theme.of(context).colorScheme.outline),
        ],
      ),
    );
  }
}

class _InlineConnectionStatus extends ConsumerWidget {
  const _InlineConnectionStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(connectionStatusProvider);
    return AppCard(
      child: statusAsync.when(
        data: (status) => switch (status) {
          Disconnected() => const StatusChip(
              icon: Icons.cloud_off_rounded,
              label: 'Connection',
              value: 'Not configured',
              severity: StatusSeverity.idle,
            ),
          Connecting() => const StatusChip(
              icon: Icons.sync_rounded,
              label: 'Connection',
              value: 'Connecting…',
              severity: StatusSeverity.info,
            ),
          Online(:final summary) => StatusChip(
              icon: Icons.cloud_done_rounded,
              label: 'Connection',
              value: summary.version ?? 'Online',
              severity: StatusSeverity.success,
            ),
          Offline(:final error) => StatusChip(
              icon: Icons.error_outline_rounded,
              label: 'Connection',
              value: error.message,
              severity: StatusSeverity.danger,
            ),
        },
        loading: () => const StatusChip(
          icon: Icons.sync_rounded,
          label: 'Connection',
          value: 'Connecting…',
          severity: StatusSeverity.info,
        ),
        error: (_, _) => const StatusChip(
          icon: Icons.error_outline_rounded,
          label: 'Connection',
          value: 'Unknown',
          severity: StatusSeverity.idle,
        ),
      ),
    );
  }
}
