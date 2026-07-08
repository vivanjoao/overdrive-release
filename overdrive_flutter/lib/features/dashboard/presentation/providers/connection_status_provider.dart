import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/result/result.dart';
import '../../../../services/backend_service.dart';
import '../../../../services/connection_controller.dart';

/// Live, polled connection state to the head unit.
///
/// Mirrors the four states the Dashboard surfaces to the user. We model it
/// as a sealed union (rather than re-using `AsyncValue<HealthSummary>`)
/// because the "no config" and "in-flight" states carry different semantics
/// than AsyncValue's loading/data/error and we want the UI to exhaustively
/// switch over them.
sealed class ConnectionStatus {
  const ConnectionStatus();
}

/// No base URL configured — Settings has not been completed yet.
final class Disconnected extends ConnectionStatus {
  const Disconnected();
}

/// A probe is in flight. Carries the previous known status so the UI can
/// keep rendering the last good state without flicker.
final class Connecting extends ConnectionStatus {
  const Connecting(this.previous);
  final ConnectionStatus? previous;
}

/// Head unit responded successfully.
final class Online extends ConnectionStatus {
  const Online(this.summary);
  final HealthSummary summary;
}

/// Last probe failed. Carries the structured [AppError] so the UI can show
/// a specific reason ("timeout", "404", "DNS failure", etc.).
final class Offline extends ConnectionStatus {
  const Offline(this.error);
  final AppError error;
}

/// Polling interval between automatic health probes.
const _kPollInterval = Duration(seconds: 10);

/// Stream of [ConnectionStatus] that auto-polls the head unit while the
/// dashboard (or any other feature) is listening.
///
/// Implementation notes:
///  * Emits [Disconnected] immediately when no URL is configured.
///  * Issues a probe on subscribe and after every [_kPollInterval].
///  * Cancels the timer when the subscription cancels, so we don't keep
///    hitting the network while the dashboard isn't mounted.
final connectionStatusProvider = StreamProvider.autoDispose<ConnectionStatus>(
  (ref) async* {
    final backend = ref.watch(backendServiceProvider);

    // Re-seed when the user edits the config in Settings.
    ref.watch(connectionControllerProvider);

    final controller = StreamController<ConnectionStatus>();

    Future<void> probe({ConnectionStatus? previous}) async {
      controller.add(Connecting(previous));
      final result = await backend.healthCheck();
      switch (result) {
        case Success(:final data):
          controller.add(Online(data));
        case Failure(:final error):
          controller.add(Offline(error));
      }
    }

    Timer? timer;
    controller.onListen = () {
      probe();
      timer = Timer.periodic(_kPollInterval, (_) => probe());
    };
    controller.onCancel = () {
      timer?.cancel();
      timer = null;
    };

    // If no URL is configured yet, emit Disconnected right away so the
    // dashboard can prompt the user to set one up.
    final config = ref.read(connectionControllerProvider);
    if (!config.isConfigured) {
      controller.add(const Disconnected());
    }

    ref.onDispose(() {
      timer?.cancel();
      controller.close();
    });

    yield* controller.stream;
  },
);
