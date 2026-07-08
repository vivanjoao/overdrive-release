import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/colors.dart';
import '../../theme/dimensions.dart';

/// Severity of a status indicator, mapped to a color and label style.
enum StatusSeverity { idle, info, success, warning, danger }

/// Compact "icon + label + colored dot" chip used to surface live state
/// (connection, sentry armed, recording, etc.).
///
/// Reused across the Dashboard, Settings, and feature pages so all status
/// cues share one visual treatment.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.severity = StatusSeverity.idle,
  });

  final IconData icon;
  final String label;
  final String value;
  final StatusSeverity severity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColors = context.statusColors;
    final (dotColor, valueColor) = _colors(theme, statusColors);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimensions.space3),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.onSurfaceVariant, size: 22),
          const SizedBox(width: AppDimensions.space12),
          Expanded(
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: AppDimensions.space8),
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
              boxShadow: severity == StatusSeverity.success ||
                      severity == StatusSeverity.danger
                  ? [
                      BoxShadow(
                        color: dotColor.withValues(alpha: 0.4),
                        blurRadius: 6,
                        spreadRadius: 0.5,
                      ),
                    ]
                  : null,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: valueColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  (Color, Color) _colors(ThemeData theme, StatusColors statusColors) {
    switch (severity) {
      case StatusSeverity.idle:
        return (
          theme.colorScheme.outline,
          theme.colorScheme.onSurfaceVariant,
        );
      case StatusSeverity.info:
        return (statusColors.info, statusColors.info);
      case StatusSeverity.success:
        return (statusColors.success, statusColors.success);
      case StatusSeverity.warning:
        return (statusColors.warning, statusColors.warning);
      case StatusSeverity.danger:
        return (statusColors.danger, statusColors.danger);
    }
  }
}
