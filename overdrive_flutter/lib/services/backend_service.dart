import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_error_mapper.dart';
import '../core/result/result.dart';
import '../core/utils/logger.dart';
import 'connection_config.dart';
import 'connection_controller.dart';

/// Talks to the OverDrive HTTP server running on the car's head unit
/// (or any tunnel fronting it).
///
/// Feature repositories (recordings, trips, vehicle state, …) consume this
/// service rather than instantiating their own HTTP clients, so connection
/// config, timeouts, error mapping, and auth are owned in one place.
abstract class BackendService {
  /// Probes whether the head unit is reachable and responding.
  ///
  /// Returns a [HealthSummary] when reachable, or an [AppError] describing
  /// why the probe failed. Never throws.
  Future<Result<HealthSummary>> healthCheck();

  /// GET [path] (relative to the head unit's base URL) and decode the body
  /// as JSON.
  ///
  /// Throws [AppError] (not [DioException]) on any failure so call sites
  /// only need one catch clause. Throws [StateError] when no connection is
  /// configured — feature code should guard against this by checking the
  /// connection status first.
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  });

  /// Builds a fully-qualified URL for a recording / asset on the head unit.
  /// Returns an empty string when no connection is configured.
  String resolveAssetUrl(String relativePath);
}

class HealthSummary {
  const HealthSummary({
    required this.url,
    this.version,
    this.daemonRunning = false,
    this.sentryArmed = false,
    this.checkedAt,
  });

  /// Base URL the probe was issued against.
  final String url;

  /// Head-unit software version, if the server reported one.
  final String? version;

  /// Whether the camera/recording daemon is alive.
  final bool daemonRunning;

  /// Whether sentry mode is currently armed.
  final bool sentryArmed;

  final DateTime? checkedAt;

  @override
  String toString() =>
      'HealthSummary(version: $version, daemon: $daemonRunning, sentry: $sentryArmed)';
}

class BackendApiService implements BackendService {
  BackendApiService(this._read);

  /// Returns the currently-active connection config. Passed in as a
  /// function so the service always sees the latest user-edited value
  /// without needing to be rebuilt.
  final ConnectionConfig Function() _read;

  @override
  Future<Result<HealthSummary>> healthCheck() async {
    final config = _read();
    if (!config.isConfigured) {
      return const Result.failure(
        NetworkError('No head unit address configured.'),
      );
    }

    final dio = _rootDio();
    final url = config.resolve('/api/status');
    try {
      final response = await dio.get<Map<String, dynamic>>(url);
      final data = response.data;
      return Result.success(HealthSummary(
        url: config.normalizedBaseUrl,
        version: data?['version'] as String?,
        daemonRunning: (data?['daemon_running'] as bool?) ?? false,
        sentryArmed: (data?['sentry_armed'] as bool?) ?? false,
        checkedAt: DateTime.now(),
      ));
    } on DioException catch (e) {
      // Some early head-unit builds don't expose /api/status yet. If we got
      // *any* HTTP response (even a 404), the server itself is alive —
      // report that as a degraded-but-reachable state rather than an error.
      if (e.type == DioExceptionType.badResponse && e.response != null) {
        AppLogger.info(
          'Head unit reachable but /api/status returned ${e.response?.statusCode}',
          name: 'backend',
        );
        return Result.success(HealthSummary(
          url: config.normalizedBaseUrl,
          checkedAt: DateTime.now(),
        ));
      }
      return Result.failure(e.toAppError());
    }
  }

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final config = _read();
    if (!config.isConfigured) {
      throw const NetworkError('No head unit address configured.');
    }
    final dio = _rootDio();
    final url = config.resolve(path);
    try {
      final response = await dio.get<dynamic>(url, queryParameters: queryParameters);
      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      // Some endpoints return a bare array or scalar; wrap for uniformity.
      return {'data': data};
    } on DioException catch (e) {
      throw e.toAppError();
    }
  }

  @override
  String resolveAssetUrl(String relativePath) {
    final config = _read();
    if (!config.isConfigured) return '';
    final cleanPath =
        relativePath.startsWith('/') ? relativePath : '/$relativePath';
    // Recording files are served by the head unit's web server directly
    // (no /api prefix), the same root that serves the embedded web UI.
    return '${config.normalizedBaseUrl}$cleanPath';
  }

  /// A bare Dio instance scoped to this probe. We don't use the global
  /// [dioProvider] here because the probe runs in isolation and we want
  /// shorter timeouts so the UI doesn't feel sluggish.
  Dio _rootDio() {
    return Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 4),
      sendTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 6),
      responseType: ResponseType.json,
      headers: {'Accept': 'application/json'},
    ));
  }
}

/// Provider for [BackendService]. Reads the live connection config from
/// [connectionControllerProvider] on every call so users see their changes
/// take effect immediately after editing the address in Settings.
final backendServiceProvider = Provider<BackendService>((ref) {
  // Watch the controller so the service instance stays subscribed to
  // URL changes; the closure lets each call read the latest value without
  // rebuilding the service.
  ref.watch(connectionControllerProvider);
  return BackendApiService(() => ref.read(connectionControllerProvider));
});
