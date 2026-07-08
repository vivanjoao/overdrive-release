import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connection_config.dart';
import 'connection_config_repository.dart';

/// Holds the active head-unit connection config and writes any change back
/// to [ConnectionConfigRepository] so it survives restarts.
///
/// Synchronous state — SharedPreferences is pre-loaded in `main()` before
/// the UI mounts, so the initial [load] is non-blocking.
class ConnectionController extends Notifier<ConnectionConfig> {
  late final ConnectionConfigRepository _repo;

  @override
  ConnectionConfig build() {
    _repo = ref.watch(connectionConfigRepositoryProvider);
    return _repo.load();
  }

  /// Updates both the in-memory state and the persisted copy.
  Future<void> update(ConnectionConfig config) async {
    state = config;
    await _repo.save(config);
  }

  Future<void> clear() async {
    state = const ConnectionConfig();
    await _repo.clear();
  }
}

final connectionControllerProvider =
    NotifierProvider<ConnectionController, ConnectionConfig>(
  ConnectionController.new,
);
