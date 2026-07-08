import '../domain/recording.dart';
import '../domain/recording_type.dart';
import 'recording_dto.dart';

/// Fetches recording metadata from the head unit.
///
/// Implementations should be cheap to construct — feature code creates them
/// on demand inside Riverpod providers. The head unit's HTTP server is the
/// single source of truth; local caching is deferred to a later module.
abstract class RecordingRepository {
  /// Returns recordings optionally filtered by [type] and a [range] window.
  ///
  /// Implementations should treat the head unit's response as best-effort:
  /// an empty list is returned if the server reports nothing for the window.
  Future<List<Recording>> list({
    RecordingType? type,
    DateTimeRange? range,
  });
}

/// Inclusive `[start, end]` window used to scope listing queries.
class DateTimeRange {
  const DateTimeRange({required this.start, required this.end});
  final DateTime start;
  final DateTime end;

  factory DateTimeRange.month(int year, int month) {
    final start = DateTime.utc(year, month);
    final end = DateTime.utc(year, month + 1, 1, 0, 0, 0, -1);
    return DateTimeRange(start: start, end: end);
  }

  factory DateTimeRange.day(int year, int month, int day) {
    final start = DateTime.utc(year, month, day);
    final end = start.copyWith(hour: 23, minute: 59, second: 59);
    return DateTimeRange(start: start, end: end);
  }
}

/// Head-unit-backed implementation that goes through [BackendService].
///
/// Endpoints (overridable via constructor for tests):
///  * `GET /api/recordings?type=<wireName>&from=<iso>&to=<iso>`
///
/// The list response can be either a bare JSON array or one of the common
/// envelope shapes (`recordings`, `items`, `data`, `results`, `clips`) —
/// [RecordingDto.fromJsonList] handles both.
class RecordingApiRepository implements RecordingRepository {
  RecordingApiRepository(this._getJson);

  final Future<Map<String, dynamic>> Function(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) _getJson;

  @override
  Future<List<Recording>> list({
    RecordingType? type,
    DateTimeRange? range,
  }) async {
    final query = <String, dynamic>{};
    if (type != null) query['type'] = type.wireName;
    if (range != null) {
      query['from'] = range.start.toIso8601String();
      query['to'] = range.end.toIso8601String();
    }
    final json = await _getJson('/api/recordings', queryParameters: query);
    return RecordingDto.fromJsonList(json);
  }
}
