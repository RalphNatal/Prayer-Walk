import 'package:flutter/material.dart';

import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';

enum StatSize { small, medium, large }

/// A labelled figure.
///
/// The numeral is Fraunces with tabular, lining figures — so a pace readout
/// does not shuffle sideways between 5:59 and 6:00, and a column of distances
/// lines up on the decimal.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.icon,
    this.size = StatSize.medium,
    this.alignment = CrossAxisAlignment.start,
    this.emphasis,
  });

  final String label;
  final String value;
  final String? unit;
  final IconData? icon;
  final StatSize size;
  final CrossAxisAlignment alignment;

  /// Overrides the numeral colour — the live screen tints the primary readout.
  final Color? emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueSize = switch (size) {
      StatSize.small => 18.0,
      StatSize.medium => 24.0,
      StatSize.large => 40.0,
    };
    final color = emphasis ?? theme.colorScheme.onSurface;

    return Semantics(
      label: '$label: $value${unit != null ? ' $unit' : ''}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: alignment,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: AppTypography.statValue(color, size: valueSize),
              ),
              if (unit != null) ...[
                const SizedBox(width: AppSpacing.xs),
                Text(
                  unit!,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: AppSpacing.xs),
              ],
              Text(label.toUpperCase(), style: theme.textTheme.labelSmall),
            ],
          ),
        ],
      ),
    );
  }
}

/// Evenly spaced stats with hairline separators. Wraps to two rows on narrow
/// screens and at large text sizes rather than clipping.
class StatStrip extends StatelessWidget {
  const StatStrip({
    super.key,
    required this.children,
    this.size = StatSize.medium,
  });

  final List<StatTile> children;
  final StatSize size;

  @override
  Widget build(BuildContext context) {
    final divider = VerticalDivider(
      width: AppSpacing.xl,
      thickness: 1,
      color: Theme.of(context).colorScheme.outlineVariant,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final perTile = constraints.maxWidth / children.length;
        final needsWrap = perTile < 88 * scale;

        if (needsWrap) {
          return Wrap(
            spacing: AppSpacing.xl,
            runSpacing: AppSpacing.lg,
            children: children,
          );
        }

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) divider,
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: children[i],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
