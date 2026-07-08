import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Synchronously-available [SharedPreferences] instance.
///
/// Initialized in `main()` before `runApp` via a provider override:
///
/// ```dart
/// final prefs = await SharedPreferences.getInstance();
/// runApp(ProviderScope(
///   overrides: [
///     sharedPreferencesProvider.overrideWithValue(prefs),
///   ],
///   child: const OverdriveApp(),
/// ));
/// ```
///
/// Keeping this synchronous (rather than a [FutureProvider]) means
/// `ConnectionController` and other bootstrap-time readers can resolve their
/// initial state without async plumbing.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main() '
    'with a pre-initialized SharedPreferences instance.',
  );
});
