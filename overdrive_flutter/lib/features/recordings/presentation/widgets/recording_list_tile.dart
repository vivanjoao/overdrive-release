import 'package:flutter/material.dart';

import '../../../../theme/dimensions.dart';
import '../../domain/recording.dart';

/// Single row in the recordings list.
///
/// Shows thumbnail (when available), title (time + camera), duration chip,
/// and size. Designed to be tappable to open [RecordingDetailSheet].
class RecordingListTile extends StatelessWidget {
  const RecordingListTile({
    super.key,
    required this.recording,
    required this.onTap,
  });

  final Recording recording;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = _formatTime(recording.startTime);
    final cameraLabel = recording.camera != null
        ? ' · ${_capitalize(recording.camera!)}'
        : '';

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.space8, vertical: AppDimensions.space3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppDimensions.radius12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppDimensions.space12, vertical: AppDimensions.space12),
            child: Row(
              children: [
                _Thumbnail(recording: recording),
                const SizedBox(width: AppDimensions.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$time$cameraLabel',
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        recording.eventCause ??
                            recording.type.displayName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppDimensions.space8),
                _MetaChips(recording: recording),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.recording});

  final Recording recording;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppDimensions.radius8),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.play_circle_outline_rounded,
            color: theme.colorScheme.primary,
            size: 28,
          ),
          Positioned(
            right: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                recording.formattedDuration,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChips extends StatelessWidget {
  const _MetaChips({required this.recording});

  final Recording recording;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          recording.formattedSize,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontFamily: 'JetBrains Mono',
          ),
        ),
      ],
    );
  }
}
