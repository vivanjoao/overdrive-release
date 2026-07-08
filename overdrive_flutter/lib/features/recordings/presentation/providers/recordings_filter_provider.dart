import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/recording_type.dart';

/// User-controlled filters for the recordings list (segment + month).
///
/// Kept separate from the list itself so changing the filter invalidates the
/// fetch via `autoDispose` + `family`-like behavior without losing the
/// filter selection.
class RecordingsFilter {
  const RecordingsFilter({
    this.type = RecordingType.dashcam,
    required this.year,
    required this.month,
  });

  final RecordingType type;

  /// 1-12
  final int month;

  /// Full year (e.g. 2026).
  final int year;

  RecordingsFilter copyWith({
    RecordingType? type,
    int? year,
    int? month,
  }) {
    return RecordingsFilter(
      type: type ?? this.type,
      year: year ?? this.year,
      month: month ?? this.month,
    );
  }

  /// Returns the filter shifted one month backwards, rolling the year.
  RecordingsFilter previousMonth() {
    if (month == 1) return copyWith(year: year - 1, month: 12);
    return copyWith(month: month - 1);
  }

  /// Returns the filter shifted one month forwards, rolling the year.
  RecordingsFilter nextMonth() {
    if (month == 12) return copyWith(year: year + 1, month: 1);
    return copyWith(month: month + 1);
  }

  /// Human label like "July 2026".
  String get monthLabel => '${_monthNames[month - 1]} $year';

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
}

class RecordingsFilterController extends Notifier<RecordingsFilter> {
  @override
  RecordingsFilter build() {
    final now = DateTime.now();
    return RecordingsFilter(year: now.year, month: now.month);
  }

  void setType(RecordingType type) => state = state.copyWith(type: type);
  void previousMonth() => state = state.previousMonth();
  void nextMonth() => state = state.nextMonth();
  void jumpToMonth(int year, int month) =>
      state = state.copyWith(year: year, month: month);
}

final recordingsFilterProvider =
    NotifierProvider<RecordingsFilterController, RecordingsFilter>(
  RecordingsFilterController.new,
);

/// Day-of-month the user tapped on the calendar (1..N, or null = none).
///
/// Riverpod 3 removed `StateProvider`; this tiny Notifier replaces it.
class SelectedDayController extends Notifier<int?> {
  @override
  int? build() => null;

  void set(int? day) => state = day;

  void clear() => state = null;
}

final selectedDayProvider =
    NotifierProvider<SelectedDayController, int?>(SelectedDayController.new);
