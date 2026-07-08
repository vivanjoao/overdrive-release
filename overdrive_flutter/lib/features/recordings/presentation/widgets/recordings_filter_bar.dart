import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/recording_type.dart';
import '../../../../theme/dimensions.dart';
import '../providers/recordings_filter_provider.dart';

/// Top control row: dashcam/surveillance segment + month navigation.
///
/// Uses a Material 3 [SegmentedButton] for the type filter (matches the
/// segmented control in the original RecordingsFragment) and a simple
/// prev/next chevron pair for month navigation.
class RecordingsFilterBar extends StatelessWidget {
  const RecordingsFilterBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.space16, vertical: AppDimensions.space8),
          child: _SegmentedTypeSelector(),
        ),
        const _MonthNavigator(),
      ],
    );
  }
}

class _SegmentedTypeSelector extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(recordingsFilterProvider.notifier);
    final current = ref.watch(recordingsFilterProvider).type;
    return SegmentedButton<RecordingType>(
      segments: [
        for (final t in RecordingType.values)
          ButtonSegment(
            value: t,
            label: Text(t.displayName),
            icon: Icon(_iconFor(t)),
          ),
      ],
      selected: {current},
      onSelectionChanged: (s) => filter.setType(s.first),
      showSelectedIcon: false,
    );
  }
}

class _MonthNavigator extends ConsumerWidget {
  const _MonthNavigator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(recordingsFilterProvider);
    final controller = ref.watch(recordingsFilterProvider.notifier);
    final theme = Theme.of(context);

    final now = DateTime.now();
    final isCurrentMonth =
        filter.year == now.year && filter.month == now.month;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.space8),
      child: Row(
        children: [
          IconButton(
            onPressed: controller.previousMonth,
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: 'Previous month',
          ),
          Expanded(
            child: Text(
              filter.monthLabel,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            onPressed: isCurrentMonth ? null : controller.nextMonth,
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: 'Next month',
          ),
        ],
      ),
    );
  }
}

IconData _iconFor(RecordingType type) => switch (type) {
      RecordingType.dashcam => Icons.videocam_outlined,
      RecordingType.surveillance => Icons.shield_outlined,
      RecordingType.proximity => Icons.sensors_rounded,
    };
