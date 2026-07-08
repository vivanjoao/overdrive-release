import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/storage/shared_preferences_provider.dart';
import 'connection_config.dart';

/// SharedPreferences-backed persistence for the active [ConnectionConfig].
///
/// Wraps the synchronous [SharedPreferences] provider so the rest of the app
/// never touches the plugin directly.
class ConnectionConfigRepository {
  ConnectionConfigRepository(this._prefs);

  static const _kBaseUrl = 'connection.base_url';
  static const _kLabel = 'connection.label';

  final SharedPreferences _prefs;

  /// Loads the stored config. Returns an unconfigured default on first
  /// launch.
  ConnectionConfig load() => ConnectionConfig(
        baseUrl: _prefs.getString(_kBaseUrl) ?? '',
        label: _prefs.getString(_kLabel) ?? 'Head unit',
      );

  Future<void> save(ConnectionConfig config) async {
    await _prefs.setString(_kBaseUrl, config.baseUrl);
    await _prefs.setString(_kLabel, config.label);
  }

  Future<void> clear() async {
    await _prefs.remove(_kBaseUrl);
    await _prefs.remove(_kLabel);
  }
}

/// Synchronous provider for [ConnectionConfigRepository].
final connectionConfigRepositoryProvider = Provider<ConnectionConfigRepository>(
  (ref) => ConnectionConfigRepository(ref.watch(sharedPreferencesProvider)),
);
