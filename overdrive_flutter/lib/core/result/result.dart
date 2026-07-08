/// A discriminated union representing the outcome of an operation.
///
/// Replaces ad-hoc try/catch + null returns in repository / service code.
/// Usage:
/// ```dart
/// final result = await repository.fetchTrips();
/// switch (result) {
///   case Success(:final data):
///     renderTrips(data);
///   case Failure(:final error):
///     showError(error);
/// }
/// ```
sealed class Result<T> {
  const Result();

  /// Constructs a successful [Result] holding [data].
  const factory Result.success(T data) = Success<T>;

  /// Constructs a failed [Result] wrapping [error].
  const factory Result.failure(AppError error) = Failure<T>;
}

/// Successful operation carrying its [data].
final class Success<T> extends Result<T> {
  const Success(this.data);

  final T data;

  @override
  String toString() => 'Success($data)';
}

/// Failed operation carrying a structured [error].
final class Failure<T> extends Result<T> {
  const Failure(this.error);

  final AppError error;

  @override
  String toString() => 'Failure($error)';
}
/// Base type for all recoverable errors surfaced to the UI.
///
/// Carries a user-presentable [message] and an optional [cause] for logging.
/// Subclass to add domain-specific detail (e.g. [NetworkError],
/// [NotFoundError]). Named `AppError` to avoid collision with the
/// `Failure<T>` result variant.
sealed class AppError {
  const AppError(this.message, {this.cause});

  /// Localized-friendly message safe to show to end users.
  final String message;

  /// Optional underlying error, kept for diagnostics only.
  final Object? cause;

  @override
  String toString() => '$runtimeType($message)';
}

/// Network / transport-level errors (timeouts, DNS, socket, 5xx, etc.).
final class NetworkError extends AppError {
  const NetworkError(super.message, {super.cause});
}

/// Server returned a non-2xx response with a meaningful status code.
final class HttpError extends AppError {
  const HttpError(super.message, {required this.statusCode, super.cause});

  final int statusCode;
}

/// Requested entity does not exist (404 semantics).
final class NotFoundError extends AppError {
  const NotFoundError(super.message, {super.cause});
}

/// Catch-all for unexpected errors that don't fit a more specific subclass.
final class UnexpectedError extends AppError {
  const UnexpectedError(super.message, {super.cause});
}
