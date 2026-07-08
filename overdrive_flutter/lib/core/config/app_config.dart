/// Application-wide configuration constants.
///
/// Centralizes static metadata so feature code never hard-codes magic values.
/// Flavor- or environment-specific values (backend URLs, feature flags) live
/// here too, and can later be swapped via `--dart-define` or a flavor system.
class AppConfig {
  const AppConfig._();

  /// Human-readable product name.
  static const String appName = 'OverDrive';

  /// Semantic version, kept in sync with pubspec via `--dart-define` in CI.
  /// Falls back to a dev value when not supplied at build time.
  static const String appVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: '0.1.0');

  /// Default HTTP port used by the OverDrive daemon running on the car's
  /// head unit. The Flutter client talks to this server when on the same
  /// network (LAN mode) or through a tunnel.
  static const int defaultHeadUnitPort = 8080;

  /// User-agent string sent with outbound HTTP requests.
  static const String httpUserAgent = 'OverDrive-Flutter/$appVersion';

  /// Default locale (BCP-47) used until the user picks one in settings.
  static const String defaultLocale = 'en';
}
