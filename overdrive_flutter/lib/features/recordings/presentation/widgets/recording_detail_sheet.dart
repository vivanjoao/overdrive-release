import 'package:flutter/material.dart';

import '../../../../theme/dimensions.dart';
import '../../domain/recording.dart';

/// Modal bottom sheet that shows recording metadata and a primary "Play"
/// action. Invoked when a recording list row is tapped.
Future<void> showRecordingDetailSheet(
  BuildContext context, {
  required Recording recording,
  required VoidCallback onPlay,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _RecordingDetailSheet(
      recording: recording,
      onPlay: () {
        Navigator.pop(ctx);
        onPlay();
      },
    ),
  );
}

class _RecordingDetailSheet extends StatelessWidget {
  const _RecordingDetailSheet({required this.recording, required this.onPlay});

  final Recording recording;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppDimensions.space20, 0, AppDimensions.space20, AppDimensions.space16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppDimensions.space12, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius:
                        BorderRadius.circular(AppDimensions.radiusFull),
                  ),
                  child: Text(
                    recording.type.displayName,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimensions.space12),
            Text(
              _formatFull(recording.startTime),
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppDimensions.space16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onPlay,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Play recording'),
              ),
            ),
            const SizedBox(height: AppDimensions.space16),
            _MetaGrid(recording: recording),
          ],
        ),
      ),
    );
  }

  static String _formatFull(DateTime dt) {
    final d = '${dt.year}-${dt.month.toString().padLeft(2, '0')}'
        '-${dt.day.toString().padLeft(2, '0')}';
    final t = '${dt.hour.toString().padLeft(2, '0')}'
        ':${dt.minute.toString().padLeft(2, '0')}'
        ':${dt.second.toString().padLeft(2, '0')}';
    return '$d  $t';
  }
}

class _MetaGrid extends StatelessWidget {
  const _MetaGrid({required this.recording});

  final Recording recording;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <(String, String)>[
      ('Duration', recording.formattedDuration),
      ('Size', recording.formattedSize),
      if (recording.camera != null)
        ('Camera', _capitalize(recording.camera!)),
      if (recording.eventCause != null)
        ('Trigger', recording.eventCause!),
      ('File', recording.fileName),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppDimensions.radius12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.space12),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              _MetaRow(label: rows[i].$1, value: rows[i].$2),
              if (i < rows.length - 1)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: AppDimensions.space3),
                  child: Divider(
                    height: 1,
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: value.contains('/') || value.contains('.mp4')
                  ? 'JetBrains Mono'
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}
