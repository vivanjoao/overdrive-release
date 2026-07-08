import 'dart:developer' as developer;

/// Lightweight logging facade.
///
/// Wraps `dart:developer.log` so call sites stay clean and we can later swap
/// to a richer backend (e.g. `package:logging` or a remote sink) without
/// touching feature code. Levels match the syslog severity convention.
enum LogLevel { verbose, debug, info, warning, error, wtf }

/// Converts a [LogLevel] to a single-character prefix for log lines.
String _letter(LogLevel level) => switch (level) {
      LogLevel.verbose => 'V',
      LogLevel.debug => 'D',
      LogLevel.info => 'I',
      LogLevel.warning => 'W',
      LogLevel.error => 'E',
      LogLevel.wtf => 'A',
    };

class AppLogger {
  AppLogger._();

  /// Minimum level emitted. Raise to suppress noise in release builds.
  static LogLevel minLevel = LogLevel.debug;

  /// Logs a structured message tagged with [name] (usually a class or
  /// feature name). The optional [error] and [stackTrace] are forwarded
  /// to the platform's native error reporter when one is attached later.
  static void log(
    LogLevel level,
    String message, {
    String name = 'overdrive',
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (level.index < minLevel.index) return;
    developer.log(
      '${_letter(level)}/$name: $message',
      name: name,
      level: level.index,
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void verbose(String message, {String name = 'overdrive'}) =>
      log(LogLevel.verbose, message, name: name);
  static void debug(String message, {String name = 'overdrive'}) =>
      log(LogLevel.debug, message, name: name);
  static void info(String message, {String name = 'overdrive'}) =>
      log(LogLevel.info, message, name: name);
  static void warning(
    String message, {
    String name = 'overdrive',
    Object? error,
    StackTrace? stackTrace,
  }) =>
      log(LogLevel.warning, message,
          name: name, error: error, stackTrace: stackTrace);
  static void error(
    String message, {
    String name = 'overdrive',
    Object? error,
    StackTrace? stackTrace,
  }) =>
      log(LogLevel.error, message,
          name: name, error: error, stackTrace: stackTrace);
}
