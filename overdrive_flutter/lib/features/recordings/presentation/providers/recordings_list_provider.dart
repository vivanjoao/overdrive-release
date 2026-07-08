import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/connection_controller.dart';
import '../../data/recording_repository.dart';
import '../../data/recording_repository_provider.dart';
import '../../domain/recording.dart';
import 'recordings_filter_provider.dart';

/// Async list of recordings matching the current [RecordingsFilter].
///
/// Re-fetches automatically whenever the filter (segment, month) or the
/// connection config changes. The repository is the single source of truth
/// — we don't cache locally in this iteration.
final recordingsListProvider =
    FutureProvider.autoDispose<List<Recording>>((ref) async {
  // Depend on filter + connection so we re-run when either changes.
  final filter = ref.watch(recordingsFilterProvider);
  final config = ref.watch(connectionControllerProvider);

  if (!config.isConfigured) {
    return const [];
  }

  final repo = ref.watch(recordingRepositoryProvider);
  final range = DateTimeRange.month(filter.year, filter.month);
  try {
    final items = await repo.list(type: filter.type, range: range);
    // Oldest first — calendar / list both expect chronological order.
    items.sort((a, b) => a.startTime.compareTo(b.startTime));
    return items;
  } catch (_) {
    // FutureProvider converts the throw into AsyncError; UI renders the
        // friendly Offline state from connectionStatusProvider so we don't
        // need to surface a second error here.
    rethrow;
  }
});
