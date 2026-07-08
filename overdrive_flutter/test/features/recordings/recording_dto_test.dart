import 'package:flutter_test/flutter_test.dart';

import 'package:overdrive_flutter/features/recordings/data/recording_dto.dart';
import 'package:overdrive_flutter/features/recordings/domain/recording.dart';
import 'package:overdrive_flutter/features/recordings/domain/recording_type.dart';

void main() {
  group('RecordingDto.fromJson', () {
    test('canonical field names parse correctly', () {
      final r = RecordingDto.fromJson({
        'id': 'rec_1',
        'type': 'dashcam',
        'start_time': '2026-07-07T15:30:00Z',
        'duration_seconds': 90,
        'size_bytes': 12345678,
        'file': 'recordings/2026/07/clip.mp4',
        'camera': 'front',
      })!;

      expect(r.id, 'rec_1');
      expect(r.type, RecordingType.dashcam);
      expect(r.startTime, DateTime.utc(2026, 7, 7, 15, 30));
      expect(r.durationSeconds, 90);
      expect(r.sizeBytes, 12345678);
      expect(r.fileName, 'recordings/2026/07/clip.mp4');
      expect(r.camera, 'front');
    });

    test('falls back to filename when id is missing', () {
      final r = RecordingDto.fromJson({
        'filename': 'clip.mp4',
        'timestamp': '2026-01-01T00:00:00Z',
      })!;
      expect(r.id, 'clip.mp4');
      expect(r.fileName, 'clip.mp4');
    });

    test('returns null when no id and no filename', () {
      expect(RecordingDto.fromJson({}), isNull);
      expect(RecordingDto.fromJson({'type': 'dashcam'}), isNull);
    });

    test('parses alternate camelCase field names', () {
      final r = RecordingDto.fromJson({
        'recording_id': 'r2',
        'kind': 'surveillance',
        'startTime': '2026-07-07T15:30:00Z',
        'duration': 60,
        'bytes': 5000,
        'filename': 's.mp4',
      })!;
      expect(r.id, 'r2');
      expect(r.type, RecordingType.surveillance);
      expect(r.durationSeconds, 60);
      expect(r.sizeBytes, 5000);
    });

    test('treats sentry/motion as surveillance kind', () {
      expect(
        RecordingDto.fromJson({'id': 'x', 'type': 'sentry'})!.type,
        RecordingType.surveillance,
      );
      expect(
        RecordingDto.fromJson({'id': 'x', 'type': 'motion'})!.type,
        RecordingType.surveillance,
      );
      expect(
        RecordingDto.fromJson({'id': 'x', 'type': 'guard'})!.type,
        RecordingType.proximity,
      );
      expect(
        RecordingDto.fromJson({'id': 'x', 'type': 'drive'})!.type,
        RecordingType.dashcam,
      );
    });

    test('parses epoch-millis timestamp as UTC', () {
      final expected = DateTime.utc(2026, 7, 7, 15, 30);
      final r = RecordingDto.fromJson({
        'id': 'x',
        'timestamp': expected.millisecondsSinceEpoch,
      })!;
      expect(r.startTime, expected);
    });

    test('parses epoch-seconds timestamp as UTC', () {
      final expected = DateTime.utc(2026, 7, 7, 15, 30);
      final r = RecordingDto.fromJson({
        'id': 'x',
        'timestamp': expected.millisecondsSinceEpoch ~/ 1000,
      })!;
      expect(r.startTime, expected);
    });

    test('parses non-ISO datetime strings like "2026-07-07 15:30:00"', () {
      // No timezone suffix → parser treats the value as UTC (matching how
      // the head unit logs timestamps) rather than local time.
      final r = RecordingDto.fromJson({
        'id': 'x',
        'date': '2026-07-07 15:30:00',
      })!;
      expect(r.startTime, DateTime.utc(2026, 7, 7, 15, 30));
    });

    test('parses numeric duration/size as strings', () {
      final r = RecordingDto.fromJson({
        'id': 'x',
        'duration': '120',
        'size_bytes': '524288',
      })!;
      expect(r.durationSeconds, 120);
      expect(r.sizeBytes, 524288);
    });

    test('parses GPS coordinates from lat/lon or lat/lng', () {
      final r1 = RecordingDto.fromJson({
        'id': 'x',
        'lat': 48.85,
        'lon': 2.35,
      })!;
      expect(r1.lat, closeTo(48.85, 0.001));
      expect(r1.lon, closeTo(2.35, 0.001));

      final r2 = RecordingDto.fromJson({
        'id': 'x',
        'latitude': '40.7',
        'longitude': '-74.0',
      })!;
      expect(r2.lat, closeTo(40.7, 0.001));
      expect(r2.lon, closeTo(-74.0, 0.001));
    });
  });

  group('RecordingDto.fromJsonList', () {
    test('bare array', () {
      final list = RecordingDto.fromJsonList([
        {'id': 'a', 'type': 'dashcam'},
        {'id': 'b', 'type': 'surveillance'},
        {'filename': 'only-file.mp4'},
        {'type': 'no-id-or-file'},
      ]);
      expect(list.length, 3);
      expect(list[0].id, 'a');
      expect(list[1].type, RecordingType.surveillance);
      expect(list[2].id, 'only-file.mp4');
    });

    test('envelope under recordings key', () {
      final list = RecordingDto.fromJsonList({
        'recordings': [
          {'id': 'r1'},
          {'id': 'r2'},
        ],
      });
      expect(list.length, 2);
    });

    test('envelope under items key', () {
      final list = RecordingDto.fromJsonList({
        'items': [{'id': 'r1'}],
      });
      expect(list.length, 1);
    });

    test('envelope under data key', () {
      final list = RecordingDto.fromJsonList({
        'data': [{'id': 'r1'}],
      });
      expect(list.length, 1);
    });

    test('single object (not a list)', () {
      final list = RecordingDto.fromJsonList({'id': 'r1'});
      expect(list.length, 1);
      expect(list.first.id, 'r1');
    });

    test('empty input returns empty list', () {
      expect(RecordingDto.fromJsonList(null), isEmpty);
      expect(RecordingDto.fromJsonList(<String, dynamic>{}), isEmpty);
    });
  });

  group('Recording formatted helpers', () {
    test('formattedDuration handles hours, minutes, seconds', () {
      Recording r(int secs) => RecordingDto.fromJson({
            'id': 'x',
            'duration_seconds': secs,
          })!;

      expect(r(45).formattedDuration, '0:45');
      expect(r(95).formattedDuration, '1:35');
      expect(r(3661).formattedDuration, '1:01:01');
    });

    test('formattedSize formats bytes correctly', () {
      Recording r(int bytes) => RecordingDto.fromJson({
            'id': 'x',
            'size_bytes': bytes,
          })!;

      expect(r(500).formattedSize, '500 B');
      expect(r(1024).formattedSize, '1.0 KB');
      expect(r(12345678).formattedSize, '11.8 MB');
      expect(r(0).formattedSize, '—');
    });
  });
}
