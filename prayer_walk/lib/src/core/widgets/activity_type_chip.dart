import 'package:flutter/material.dart';

import '../../features/activity/domain/activity.dart';
import '../constants/app_spacing.dart';

/// Icons for the four activity types.
///
/// `ActivityType` is the one piece of feature vocabulary the shared kit knows
/// about: feed, history, record and admin all speak it, and duplicating the
/// icon mapping in each of them would guarantee they drift apart.
abstract final class ActivityTypeVisuals {
  static IconData icon(ActivityType type) => switch (type) {
    ActivityType.walk => Icons.directions_walk_rounded,
    ActivityType.run => Icons.directions_run_rounded,
    ActivityType.hike => Icons.hiking_rounded,
    ActivityType.cycle => Icons.directions_bike_rounded,
  };
}

/// A read-only marker of what kind of activity this was.
class ActivityTypeChip extends StatelessWidget {
  const ActivityTypeChip({super.key, required this.type, this.compact = false});

  final ActivityType type;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.sm : AppSpacing.md,
        vertical: compact ? AppSpacing.xxs : AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: AppRadius.chip,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ActivityTypeVisuals.icon(type),
            size: compact ? 13 : 15,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            type.label,
            style: (compact ? theme.textTheme.labelSmall : theme.textTheme.labelMedium)
                ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
          ),
        ],
      ),
    );
  }
}

/// The selectable variant: activity-type filters on History, and the type
/// picker on Record.
class ActivityTypeFilterChip extends StatelessWidget {
  const ActivityTypeFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FilterChip(
      selected: selected,
      onSelected: (_) => onSelected(),
      avatar: icon == null
          ? null
          : Icon(
              icon,
              size: 18,
              color: selected
                  ? theme.colorScheme.onSecondaryContainer
                  : theme.colorScheme.onSurfaceVariant,
            ),
      label: Text(label),
      // A 48dp row height is preserved by the surrounding list padding; the
      // chip itself stays visually compact.
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }
}
