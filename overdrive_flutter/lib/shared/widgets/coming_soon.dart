import 'package:flutter/material.dart';

import '../../theme/dimensions.dart';
import 'empty_state.dart';

/// Stand-in page for features whose module has not been implemented yet.
///
/// Each iteration of the build plan replaces one [ComingSoonPage] with the
/// real feature. Keeping the placeholder in the routing tree from day one
/// means navigation, deep links, and the adaptive shell can be validated
/// end-to-end without waiting for feature work.
class ComingSoonPage extends StatelessWidget {
  const ComingSoonPage({
    super.key,
    required this.title,
    required this.icon,
    this.step,
  });

  final String title;
  final IconData icon;

  /// Build-plan step that will deliver this feature, used in the message.
  final String? step;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: icon,
      title: '$title is coming soon',
      message: step == null
          ? 'This module lands in a later iteration of the build plan.'
          : 'Scheduled for $step.',
    );
  }
}

/// A simple section header used inside feature pages.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.space4, vertical: AppDimensions.space8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
