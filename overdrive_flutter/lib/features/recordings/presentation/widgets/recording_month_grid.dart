import 'package:flutter/material.dart';

import '../../../../theme/dimensions.dart';
import '../../domain/recording.dart';
import '../providers/recordings_filter_provider.dart';

/// Compact month calendar with day indicators showing recording density.
///
/// Days with at least one recording get a tinted circle; days without stay
/// plain. Tapping a day selects it and the parent filters the list below.
///
/// Implemented from scratch (rather than pulling `table_calendar` or
/// similar) to keep the dependency surface small and the visual treatment
/// exactly aligned with the M3 theme tokens.
class RecordingMonthGrid extends StatelessWidget {
  const RecordingMonthGrid({
    super.key,
    required this.filter,
    required this.recordings,
    required this.selectedDay,
    required this.onDaySelected,
  });

  final RecordingsFilter filter;
  final List<Recording> recordings;
  final int? selectedDay;
  final ValueChanged<int> onDaySelected;

  @override
  Widget build(BuildContext context) {
    final counts = _countByDay(recordings, filter.year, filter.month);
    final firstWeekday = DateTime.utc(filter.year, filter.month, 1).weekday;
    // Convert Monday=1..Sunday=7 to our Sunday-first layout.
    final leadingBlanks = (firstWeekday % 7);
    final daysInMonth = DateTime.utc(filter.year, filter.month + 1, 0).day;

    return Column(
      children: [
        _WeekdayHeader(),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.space8, vertical: AppDimensions.space4),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
          ),
          itemCount: leadingBlanks + daysInMonth,
          itemBuilder: (context, index) {
            if (index < leadingBlanks) return const SizedBox.shrink();
            final day = index - leadingBlanks + 1;
            final count = counts[day] ?? 0;
            return _DayCell(
              day: day,
              count: count,
              selected: day == selectedDay,
              isToday: _isToday(filter.year, filter.month, day),
              onTap: () => onDaySelected(day),
            );
          },
        ),
      ],
    );
  }

  static Map<int, int> _countByDay(
      List<Recording> recordings, int year, int month) {
    final counts = <int, int>{};
    for (final r in recordings) {
      if (r.startTime.year == year && r.startTime.month == month) {
        final d = r.startTime.day;
        counts[d] = (counts[d] ?? 0) + 1;
      }
    }
    return counts;
  }

  static bool _isToday(int year, int month, int day) {
    final now = DateTime.now();
    return now.year == year && now.month == month && now.day == day;
  }
}

class _WeekdayHeader extends StatelessWidget {
  static const _labels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.space8),
      child: Row(
        children: [
          for (final l in _labels)
            Expanded(
              child: Center(
                child: Text(
                  l,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.count,
    required this.selected,
    required this.isToday,
    required this.onTap,
  });

  final int day;
  final int count;
  final bool selected;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasRecordings = count > 0;

    final backgroundColor = selected
        ? theme.colorScheme.primary
        : hasRecordings
            ? theme.colorScheme.secondaryContainer
            : Colors.transparent;

    final foregroundColor = selected
        ? theme.colorScheme.onPrimary
        : hasRecordings
            ? theme.colorScheme.onSecondaryContainer
            : theme.colorScheme.onSurface;

    return InkWell(
      borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: backgroundColor,
            shape: BoxShape.circle,
            border: isToday && !selected
                ? Border.all(color: theme.colorScheme.primary, width: 1.5)
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$day',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: foregroundColor,
                  fontWeight: selected || isToday
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
              ),
              if (hasRecordings && !selected)
                Container(
                  width: 4,
                  height: 4,
                  margin: const EdgeInsets.only(top: 1),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
