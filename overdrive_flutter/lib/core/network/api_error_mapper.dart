import 'package:dio/dio.dart';

import '../result/result.dart';

/// Extension that converts a [DioException] into a structured [AppError].
///
/// Repository / service code should never let a raw [DioException] escape to
/// the UI. Wrap every call in `try/catch` and call [toAppError] to produce a
/// user-presentable error:
///
/// ```dart
/// try {
///   final response = await dio.get('/status');
///   return Result.success(response.data);
/// } on DioException catch (e) {
///   return Result.failure(e.toAppError());
/// }
/// ```
extension DioExceptionX on DioException {
  AppError toAppError() {
    switch (type) {
      case DioExceptionType.connectionTimeout:
        return const NetworkError('Connection timed out. Is the head unit reachable?');
      case DioExceptionType.sendTimeout:
        return const NetworkError('Request send timed out.');
      case DioExceptionType.receiveTimeout:
        return const NetworkError('The head unit took too long to respond.');
      case DioExceptionType.connectionError:
        // DNS failure, connection refused, network unreachable, etc.
        final msg = error?.toString() ?? message ?? 'Could not reach the head unit.';
        return NetworkError(_cleanConnectionMessage(msg));
      case DioExceptionType.badCertificate:
        return const NetworkError('The head unit presented an invalid TLS certificate.');
      case DioExceptionType.badResponse:
        return _errorForStatus(response?.statusCode ?? 0);
      case DioExceptionType.cancel:
        return const UnexpectedError('Request was cancelled.');
      case DioExceptionType.unknown:
      default:
        final msg = error?.toString() ?? message ?? 'Unexpected network error.';
        return UnexpectedError(msg);
    }
  }

  AppError _errorForStatus(int status) {
    if (status == 404) {
      return const NotFoundError('Endpoint not found on the head unit.');
    }
    if (status >= 500) {
      return HttpError(
        'The head unit reported an error (HTTP $status).',
        statusCode: status,
      );
    }
    return HttpError(
      'Request rejected by the head unit (HTTP $status).',
      statusCode: status,
    );
  }
}

/// Cleans up platform-specific connection-error messages so the user gets a
/// consistent, friendly string regardless of whether they're on iOS, Android,
/// or web.
String _cleanConnectionMessage(String raw) {
  // Web messages tend to wrap the actual reason in "Failed to fetch: <x>".
  if (raw.startsWith('Failed to fetch')) {
    return 'Could not reach the head unit. Check the address and network.';
  }
  // Trim excessively long socket traces.
  if (raw.length > 120) {
    return '${raw.substring(0, 117)}...';
  }
  return raw;
}
