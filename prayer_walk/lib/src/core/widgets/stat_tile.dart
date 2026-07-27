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

  /// The type size of the numeral at each [StatSize].
  static double valueFontSize(StatSize size) => switch (size) {
    StatSize.small => 18.0,
    StatSize.medium => 24.0,
    StatSize.large => 40.0,
  };

  /// How wide the tile wants to be before anything has to give: enough for the
  /// widest readout it carries — a pace of `16:40` with its `/km` — and the
  /// uppercase label beneath it, at [valueFontSize] and text scale 1.
  ///
  /// [StatStrip] compares against this to decide between one row and two. It is
  /// a want, not a floor: below it the tile still draws, scaled down.
  static double preferredWidth(StatSize size) => switch (size) {
    StatSize.small => 68.0,
    StatSize.medium => 88.0,
    StatSize.large => 140.0,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueSize = valueFontSize(size);
    final color = emphasis ?? theme.colorScheme.onSurface;
    final start = alignment == CrossAxisAlignment.center
        ? Alignment.center
        : alignment == CrossAxisAlignment.end
        ? Alignment.centerRight
        : Alignment.centerLeft;

    return Semantics(
      label: '$label: $value${unit != null ? ' $unit' : ''}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: alignment,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The numeral and its unit are one reading and share a baseline, so
          // they shrink together rather than the unit wrapping away from the
          // figure it belongs to. `scaleDown` is a last resort — it only bites
          // when the slot is narrower than the tile wants, and it never
          // enlarges, so the type scale is untouched everywhere else.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: start,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  softWrap: false,
                  style: AppTypography.statValue(color, size: valueSize),
                ),
                if (unit != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    unit!,
                    maxLines: 1,
                    softWrap: false,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: AppSpacing.xs),
              ],
              // A long label ellipsises rather than pushing the tile wider than
              // its slot. The figure above it stays whole.
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
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
  const StatStrip({super.key, required this.children});

  final List<StatTile> children;

  /// Width of one [VerticalDivider] between two tiles. The divider's `width` is
  /// its whole footprint — the hairline plus the air either side — so this is
  /// what the row spends on separators.
  static const double dividerWidth = AppSpacing.xl;

  /// Keeps the wrap decision off the knife edge. Without it a strip whose tiles
  /// come out to exactly their preferred width takes the single-row path with
  /// nothing to spare, and the first slightly-wider readout overflows.
  static const double wrapMargin = 4;

  @override
  Widget build(BuildContext context) {
    final divider = VerticalDivider(
      width: dividerWidth,
      thickness: 1,
      color: Theme.of(context).colorScheme.outlineVariant,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // The row this falls through to spends `children.length - 1` dividers'
        // worth of width before a tile gets any. Dividing the full width by the
        // tile count — as this once did — overstates the slot by 24dp a divider
        // and takes the single-row path on screens where it does not fit.
        final dividerBudget = (children.length - 1) * dividerWidth;
        final perTile =
            (constraints.maxWidth - dividerBudget) / children.length;

        // The widest tile decides for all of them: the row gives every tile the
        // same slot. Scaled by how much larger the text actually renders at the
        // reader's setting, measured at the numeral's own size rather than at
        // an abstract 1.0 — Android's scaling curve is not linear.
        final scaler = MediaQuery.textScalerOf(context);
        var wanted = 0.0;
        for (final tile in children) {
          final fontSize = StatTile.valueFontSize(tile.size);
          final ratio = scaler.scale(fontSize) / fontSize;
          final want = StatTile.preferredWidth(tile.size) * ratio;
          if (want > wanted) wanted = want;
        }

        // An unbounded strip has no slots to divide, and the row path's
        // `Expanded` cannot lay out in infinite width. Wrapping is the honest
        // answer there too: the tiles line up at their own size.
        final needsWrap =
            !constraints.hasBoundedWidth || perTile < wanted + wrapMargin;

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
