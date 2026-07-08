import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/backend_service.dart';
import 'recording_repository.dart';

/// Provides the active [RecordingRepository].
///
/// Backed by [BackendService] — when the user changes the head unit address
/// in Settings, the underlying [BackendService] rebuilds and this repository
/// picks up the new base URL on the next call.
final recordingRepositoryProvider = Provider<RecordingRepository>((ref) {
  final backend = ref.watch(backendServiceProvider);
  return RecordingApiRepository(backend.getJson);
});
