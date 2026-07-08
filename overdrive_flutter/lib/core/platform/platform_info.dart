import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Centralized platform detection.
///
/// Hides the `kIsWeb` + `Platform.*` ceremony behind named getters so the
/// rest of the app asks declarative questions ("is this a phone-shaped
/// client that can reach BYD Cloud?") instead of inspecting the OS directly.
class PlatformInfo {
  PlatformInfo._();

  /// True only when running as a web app (including iOS-installed PWA).
  static bool get isWeb => kIsWeb;

  static bool get isAndroid => !isWeb && Platform.isAndroid;
  static bool get isIOS => !isWeb && Platform.isIOS;
  static bool get isMacOS => !isWeb && Platform.isMacOS;
  static bool get isWindows => !isWeb && Platform.isWindows;
  static bool get isLinux => !isWeb && Platform.isLinux;
  static bool get isFuchsia => !isWeb && Platform.isFuchsia;

  /// True when running on the BYD head unit (Android-on-the-car).
  ///
  /// The head unit is the only platform where the daemon, BYD HAL, and
  /// local sentry/recording are available. Detected heuristically — refined
  /// once we ship a platform-channel probe (see [services/platform/]).
  static bool get isHeadUnit => false;

  /// Role this build plays in the OverDrive ecosystem.
  ///
  /// `client`  — phone / tablet / PDA / PWA used to view and control remotely.
  /// `headUnit`— the Android APK running on the car (not built from this tree).
  static ClientRole get role => isHeadUnit ? ClientRole.headUnit : ClientRole.client;
}

/// High-level role the running build performs.
enum ClientRole { client, headUnit }
