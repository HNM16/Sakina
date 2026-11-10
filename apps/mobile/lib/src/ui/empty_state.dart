import 'package:flutter/material.dart';

import '../layout.dart';
import '../theme.dart';

/// The shape a screen takes when it has nothing to show.
///
/// Shared rather than per-section on purpose: "nothing here" is a state every
/// section reaches, and three different answers to it is how an app starts
/// feeling assembled from parts.
///
/// An empty state names what will be here and, where there is one, offers the
/// action that fills it. A shrug is not an empty state — see docs/UX.md on the
/// chat list's version, which is the same rule.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;

  /// The way out, when there is one. Calls and Explore have none yet, and
  /// inventing a button that does nothing would be worse than its absence.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final layout = SakinaLayout.of(context);
    final palette = SakinaPalette.of(context);
    final text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: layout.gutter * 1.5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: palette.muted),
            SizedBox(height: layout.gap * 1.2),
            Text(title, style: text.titleMedium, textAlign: TextAlign.center),
            SizedBox(height: layout.gap * 0.5),
            Text(
              body,
              style: text.bodyMedium?.copyWith(color: palette.muted),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              SizedBox(height: layout.gap * 1.4),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
