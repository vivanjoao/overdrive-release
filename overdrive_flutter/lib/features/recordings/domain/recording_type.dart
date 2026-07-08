/// Top-level category of a recording.
///
/// Mirrors the segmented control in the original Android RecordingsFragment
/// (Dashcam vs Surveillance), plus the market-first Proximity clip type that
/// the proximity-guard mode produces.
enum RecordingType {
  /// Continuous / drive-mode recording from the dashcam pipeline.
  dashcam,

  /// Motion-triggered sentry clips (event ID, cause, ROI, etc.).
  surveillance,

  /// Proximity-guard clips fired by the BYD radar sensors.
  proximity;

  /// Stable string used in API query parameters and persistence.
  String get wireName => switch (this) {
        RecordingType.dashcam => 'dashcam',
        RecordingType.surveillance => 'surveillance',
        RecordingType.proximity => 'proximity',
      };

  static RecordingType fromWire(String? value) {
    switch (value?.toLowerCase()) {
      case 'surveillance':
      case 'sentry':
      case 'motion':
        return RecordingType.surveillance;
      case 'proximity':
      case 'guard':
        return RecordingType.proximity;
      case 'dashcam':
      case 'drive':
      case 'continuous':
      default:
        return RecordingType.dashcam;
    }
  }

  String get displayName => switch (this) {
        RecordingType.dashcam => 'Dashcam',
        RecordingType.surveillance => 'Surveillance',
        RecordingType.proximity => 'Proximity',
      };
}
