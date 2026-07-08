import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../utils/logger.dart';
import 'api_error_mapper.dart';

/// Builds and provides the [Dio] HTTP client used to talk to the OverDrive
/// head unit (or any tunnel fronting it).
///
/// The base URL is **not** baked in here — feature code must always pass a
/// fully-qualified URL (or set `dio.options.baseUrl` per-request via the
/// [ConnectionController]). This avoids surprises when the user has no
/// connection configured yet.
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      sendTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      responseType: ResponseType.json,
      headers: {
        'User-Agent': AppConfig.httpUserAgent,
        'Accept': 'application/json',
      },
    ),
  );

  // Map every DioException to an AppError so call sites never need to
  // import dio directly to handle failures. Logging happens here so we get
  // one structured line per request regardless of feature code.
  dio.interceptors.add(
    InterceptorsWrapper(
      onError: (e, handler) {
        AppLogger.warning(
          'HTTP ${e.requestOptions.method} ${e.requestOptions.path} → ${e.type}',
          name: 'http',
          error: e.error,
        );
        handler.next(e);
      },
    ),
  );

  ref.onDispose(() => dio.close(force: true));
  return dio;
});

/// Convenience wrapper around [dioProvider] that re-throws any [DioException]
/// as a structured [AppError]. Use inside repository methods to keep
/// the error-handling boilerplate to a single `try/catch`:
///
/// ```dart
/// final data = await withDio((dio) => dio.get('/status').then((r) => r.data));
/// ```
Future<T> withDio<T>(
  Ref ref,
  Future<T> Function(Dio dio) action,
) async {
  final dio = ref.read(dioProvider);
  try {
    return await action(dio);
  } on DioException catch (e) {
    throw e.toAppError();
  }
}
