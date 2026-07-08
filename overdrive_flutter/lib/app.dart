import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'l10n/generated/app_localizations.dart';
import 'routing/app_router.dart';
import 'theme/app_theme.dart';

/// Root widget for the OverDrive client.
///
/// Owns the [MaterialApp.router] configuration: theme, localization, and
/// the go_router instance. Consumer so we can later read providers (e.g. a
/// theme-mode notifier) without prop-drilling.
class OverdriveApp extends ConsumerWidget {
  const OverdriveApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);

    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,

      // ── Theme ───────────────────────────────────────────────────────
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,

      // ── Routing ─────────────────────────────────────────────────────
      routerConfig: router,

      // ── Localization ────────────────────────────────────────────────
      locale: const Locale(AppConfig.defaultLocale),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
    );
  }
}
