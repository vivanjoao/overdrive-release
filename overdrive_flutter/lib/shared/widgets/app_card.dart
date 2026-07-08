import 'package:flutter/material.dart';

import '../../theme/dimensions.dart';

/// A surface-level card with consistent padding and rounded corners.
///
/// Thin wrapper around [Card] so feature widgets share one visual treatment
/// and a future redesign is a single-file change.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppDimensions.space16),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimensions.radius16),
      child: card,
    );
  }
}
