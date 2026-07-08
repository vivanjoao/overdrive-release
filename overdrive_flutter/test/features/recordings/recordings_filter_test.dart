import 'package:flutter_test/flutter_test.dart';

import 'package:overdrive_flutter/features/recordings/presentation/providers/recordings_filter_provider.dart';
import 'package:overdrive_flutter/features/recordings/domain/recording_type.dart';

void main() {
  group('RecordingsFilter', () {
    test('previousMonth rolls the year back from January', () {
      const f = RecordingsFilter(year: 2026, month: 1);
      final p = f.previousMonth();
      expect(p.year, 2025);
      expect(p.month, 12);
    });

    test('nextMonth rolls the year forward from December', () {
      const f = RecordingsFilter(year: 2026, month: 12);
      final n = f.nextMonth();
      expect(n.year, 2027);
      expect(n.month, 1);
    });

    test('previousMonth/nextMonth preserve type', () {
      const f = RecordingsFilter(
          year: 2026, month: 6, type: RecordingType.surveillance);
      expect(f.previousMonth().type, RecordingType.surveillance);
      expect(f.nextMonth().type, RecordingType.surveillance);
    });

    test('monthLabel formats as "July 2026"', () {
      const f = RecordingsFilter(year: 2026, month: 7);
      expect(f.monthLabel, 'July 2026');
    });

    test('copyWith preserves unspecified fields', () {
      const f = RecordingsFilter(year: 2026, month: 6);
      final updated = f.copyWith(type: RecordingType.proximity);
      expect(updated.year, 2026);
      expect(updated.month, 6);
      expect(updated.type, RecordingType.proximity);
    });
  });
}
