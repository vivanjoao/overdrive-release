import 'recording_type.dart';

/// Immutable snapshot of one recording on the head unit.
///
/// Field names map to what the head unit API returns today, but the parsing
/// in `RecordingDto.fromJson` tolerates several field-name variants so the
/// client keeps working if the server-side schema tweaks.
class Recording {
  const Recording({
    required this.id,
    required this.type,
    required this.startTime,
    required this.durationSeconds,
    required this.sizeBytes,
    required this.fileName,
    this.camera,
    this.eventCause,
    this.thumbnailPath,
    this.lat,
    this.lon,
  });

  /// Stable identifier on the head unit (filename or DB row id).
  final String id;

  final RecordingType type;

  /// Start of the recording (UTC).
  final DateTime startTime;

  /// Duration in seconds. `0` when unknown.
  final int durationSeconds;

  /// File size in bytes. `0` when unknown.
  final int sizeBytes;

  /// Path under the head unit's web root, used to build the playback URL.
  /// e.g. `recordings/2024/07/20240707_1530_dashcam.mp4`
  final String fileName;

  /// Source camera (front/rear/left/right/panoramic), if known.
  final String? camera;

  /// For surveillance clips: the trigger cause (motion/person/vehicle).
  final String? eventCause;

  /// Optional thumbnail path on the head unit (PNG/JPG/WebP).
  final String? thumbnailPath;

  /// Optional GPS coordinates captured with the clip.
  final double? lat;
  final double? lon;

  /// End time computed from start + duration (convenience for UI).
  DateTime get endTime =>
      startTime.add(Duration(seconds: durationSeconds));

  /// Formatted duration `H:MM:SS` (or `M:SS` when under an hour).
  String get formattedDuration {
    final h = durationSeconds ~/ 3600;
    final m = (durationSeconds % 3600) ~/ 60;
    final s = durationSeconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// Human-readable file size (e.g. `42.3 MB`).
  String get formattedSize {
    if (sizeBytes <= 0) return '—';
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = sizeBytes.toDouble();
    var u = 0;
    while (size >= 1024 && u < units.length - 1) {
      size /= 1024;
      u++;
    }
    return '${size.toStringAsFixed(u == 0 ? 0 : 1)} ${units[u]}';
  }

  @override
  String toString() =>
      'Recording($type, $fileName, ${startTime.toIso8601String()})';
}
