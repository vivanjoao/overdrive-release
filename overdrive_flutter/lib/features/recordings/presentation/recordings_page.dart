import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../services/backend_service.dart';
import '../../../services/connection_controller.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/status_chip.dart';
import '../../../theme/dimensions.dart';
import '../domain/recording.dart';
import 'providers/recordings_filter_provider.dart';
import 'providers/recordings_list_provider.dart';
import 'recording_player_page.dart';
import 'widgets/recording_detail_sheet.dart';
import 'widgets/recordings_filter_bar.dart';
import 'widgets/recording_list_tile.dart';
import 'widgets/recording_month_grid.dart';

/// Recordings library: calendar + list with adaptive layout.
///
/// Filters by type (segmented) and month, then shows a day-by-day breakdown
/// of the selected month. Tapping a recording opens the detail sheet with a
/// Play action that launches the fullscreen video player.
class RecordingsPage extends ConsumerWidget {
  const RecordingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(connectionControllerProvider);

    if (!config.isConfigured) {
      return Scaffold(
        appBar: AppBar(title: const Text('Recordings')),
        body: EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'No connection configured',
          message:
              'Add your head unit address in Settings to browse recordings.',
          action: FilledButton.tonal(
            onPressed: () => context.go('/settings/connection'),
            child: const Text('Open Settings'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Recordings')),
      body: const CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: RecordingsFilterBar()),
          SliverToBoxAdapter(child: SizedBox(height: AppDimensions.space8)),
          SliverToBoxAdapter(child: _CalendarCard()),
          SliverToBoxAdapter(child: SizedBox(height: AppDimensions.space16)),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: AppDimensions.space20),
              child: _ListHeader(),
            ),
          ),
          _RecordingsSliverList(),
          SliverToBoxAdapter(child: SizedBox(height: AppDimensions.space24)),
        ],
      ),
    );
  }
}

class _CalendarCard extends ConsumerWidget {
  const _CalendarCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(recordingsFilterProvider);
    final listAsync = ref.watch(recordingsListProvider);
    final selectedDay = ref.watch(selectedDayProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.space16),
      child: AppCard(
        child: listAsync.when(
          data: (recordings) => RecordingMonthGrid(
            filter: filter,
            recordings: recordings,
            selectedDay: selectedDay,
            onDaySelected: (day) =>
                ref.read(selectedDayProvider.notifier).set(day),
          ),
          loading: () => const SizedBox(
            height: 240,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => const SizedBox(
            height: 120,
            child: Center(
              child: StatusChip(
                icon: Icons.error_outline_rounded,
                label: 'Calendar',
                value: 'Could not load month',
                severity: StatusSeverity.danger,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ListHeader extends ConsumerWidget {
  const _ListHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(recordingsFilterProvider);
    final selectedDay = ref.watch(selectedDayProvider);
    final theme = Theme.of(context);

    final title = selectedDay == null
        ? '${filter.monthLabel} — all days'
        : '${filter.monthLabel} — day $selectedDay';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimensions.space8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _RecordingsSliverList extends ConsumerWidget {
  const _RecordingsSliverList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(recordingsListProvider);
    final selectedDay = ref.watch(selectedDayProvider);

    return listAsync.when(
      data: (recordings) {
        final filtered = selectedDay == null
            ? recordings
            : recordings
                .where((r) => r.startTime.day == selectedDay)
                .toList(growable: false);

        if (filtered.isEmpty) {
          return const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.video_library_outlined,
              title: 'No recordings',
              message:
                  'No clips in this range. Try another month or change the type filter.',
            ),
          );
        }

        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final r = filtered[index];
              return RecordingListTile(
                recording: r,
                onTap: () => _openDetail(context, ref, r),
              );
            },
            childCount: filtered.length,
          ),
        );
      },
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(AppDimensions.space32),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.space16),
          child: AppCard(
            child: Column(
              children: [
                const StatusChip(
                  icon: Icons.error_outline_rounded,
                  label: 'Head unit',
                  value: 'Could not fetch recordings',
                  severity: StatusSeverity.danger,
                ),
                const SizedBox(height: AppDimensions.space12),
                Text(
                  e.toString(),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontFamily: 'JetBrains Mono',
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openDetail(
    BuildContext context,
    WidgetRef ref,
    Recording recording,
  ) async {
    final backend = ref.read(backendServiceProvider);
    await showRecordingDetailSheet(
      context,
      recording: recording,
      onPlay: () {
        final url = backend.resolveAssetUrl(recording.fileName);
        if (url.isEmpty) return;
        context.go(
          '/recordings/player',
          extra: PlayerParams(url: url, title: recording.fileName),
        );
      },
    );
  }
}
