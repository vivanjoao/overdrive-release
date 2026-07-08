import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/storage/shared_preferences_provider.dart';
import 'core/utils/logger.dart';

/// Entry point.
///
/// Pre-initializes SharedPreferences so bootstrap-time providers (e.g.
/// [ConnectionController]) can read persisted state synchronously, then
/// injects the instance via a provider override.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Quiet down logging in release; full detail in debug.
  AppLogger.minLevel = kReleaseMode ? LogLevel.info : LogLevel.debug;

  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const OverdriveApp(),
    ),
  );
}
