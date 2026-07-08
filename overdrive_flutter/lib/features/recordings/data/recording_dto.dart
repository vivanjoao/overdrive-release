import '../domain/recording.dart';
import '../domain/recording_type.dart';

/// Wire-format representation of a recording returned by the head unit API.
///
/// The parser accepts multiple field-name conventions so the client keeps
/// working against both the canonical OverDrive schema and minor variants
/// observed across head-unit firmware revisions.
class RecordingDto {
  const RecordingDto._();

  /// Parses a single recording object. Returns null when the input lacks
  /// enough information to construct a [Recording] (no id and no fileName).
  static Recording? fromJson(Map<String, dynamic> json) {
    final id = _string(json, ['id', 'recording_id', 'uuid', '_id']) ??
        _string(json, ['file', 'filename', 'path']);
    if (id == null || id.isEmpty) return null;

    final fileName = _string(json, ['file', 'filename', 'path', 'file_name']) ??
        _string(json, ['url', 'video_url']) ??
        id;

    final type = RecordingType.fromWire(
      _string(json, ['type', 'kind', 'category']),
    );

    final start = _dateTime(json, [
      'start_time', 'startTime', 'timestamp', 'time',
      'date', 'created_at', 'createdAt',
    ]) ?? DateTime.now();

    final duration = _int(json, [
      'duration_seconds', 'duration', 'length', 'duration_secs', 'secs',
    ]);

    final size = _int(json, [
      'size_bytes', 'size', 'bytes', 'file_size', 'filesize',
    ]);

    return Recording(
      id: id,
      type: type,
      startTime: start,
      durationSeconds: duration,
      sizeBytes: size,
      fileName: fileName,
      camera: _string(json, ['camera', 'source', 'cam']),
      eventCause: _string(json, ['event_cause', 'cause', 'reason', 'trigger']),
      thumbnailPath: _string(json, ['thumbnail', 'thumb', 'poster', 'preview']),
      lat: _double(json, ['lat', 'latitude']),
      lon: _double(json, ['lon', 'lng', 'longitude']),
    );
  }

  /// Parses a list response. Accepts either a bare JSON array or the common
  /// `{ "recordings": [...] }` / `{ "items": [...] }` envelope.
  static List<Recording> fromJsonList(dynamic json) {
    if (json is! Map<String, dynamic>) return _parseArray(json);
    final envelopeKeys = ['recordings', 'items', 'data', 'results', 'clips'];
    for (final key in envelopeKeys) {
      final v = json[key];
      if (v is List) return _parseArray(v);
    }
    // Single object masquerading as a list response.
    final single = fromJson(json);
    return single == null ? const [] : [single];
  }

  static List<Recording> _parseArray(dynamic raw) {
    if (raw is! List) return const [];
    final out = <Recording>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        final r = fromJson(item);
        if (r != null) out.add(r);
      }
    }
    return out;
  }

  // ── Defensive field accessors ──────────────────────────────────────────

  static String? _string(Map<String, dynamic> json, List<String> keys) {
    for (final k in keys) {
      final v = json[k];
      if (v is String && v.isNotEmpty) return v;
      if (v is num || v is bool) return v.toString();
    }
    return null;
  }

  static int _int(Map<String, dynamic> json, List<String> keys) {
    for (final k in keys) {
      final v = json[k];
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) {
        final parsed = int.tryParse(v);
        if (parsed != null) return parsed;
        final d = double.tryParse(v);
        if (d != null) return d.toInt();
      }
    }
    return 0;
  }

  static double? _double(Map<String, dynamic> json, List<String> keys) {
    for (final k in keys) {
      final v = json[k];
      if (v is double) return v;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
    }
    return null;
  }

  static DateTime? _dateTime(Map<String, dynamic> json, List<String> keys) {
    for (final k in keys) {
      final v = json[k];
      if (v == null) continue;
      // Numeric epoch (seconds or millis).
      if (v is num) {
        final ms = v > 1e12 ? v.toInt() : (v.toInt() * 1000);
        return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
      }
      if (v is String) {
        // ISO-8601 with explicit timezone (Z or offset) → DateTime.parse
        // gives the correct instant. Without a zone, DateTime.parse treats
        // the value as local time and we'd mis-convert; fall through to the
        // custom parser below which stamps the value as UTC directly.
        final hasTz = RegExp(r'[zZ]|[+-]\d{2}:?\d{2}$').hasMatch(v);
        if (hasTz) {
          final iso = DateTime.tryParse(v);
          if (iso != null) return iso.toUtc();
        }
        for (final fmt in ['yyyy-MM-dd HH:mm:ss', 'yyyy/MM/dd HH:mm:ss']) {
          final parsed = _tryFormat(v, fmt);
          if (parsed != null) return parsed;
        }
      }
    }
    return null;
  }

  // Minimal hand-rolled parser so we don't pull in intl/package:intl just
  // for two format strings.
  static DateTime? _tryFormat(String value, String pattern) {
    try {
      final parts = <String>[];
      var current = '';
      for (final ch in value.split('')) {
        if (RegExp(r'[0-9]').hasMatch(ch)) {
          current += ch;
        } else {
          if (current.isNotEmpty) parts.add(current);
          current = '';
        }
      }
      if (current.isNotEmpty) parts.add(current);
      if (parts.length < 3) return null;
      final y = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      final d = int.parse(parts[2]);
      final hh = parts.length > 3 ? int.parse(parts[3]) : 0;
      final mm = parts.length > 4 ? int.parse(parts[4]) : 0;
      final ss = parts.length > 5 ? int.parse(parts[5]) : 0;
      return DateTime.utc(y, m, d, hh, mm, ss);
    } catch (_) {
      return null;
    }
  }
}
