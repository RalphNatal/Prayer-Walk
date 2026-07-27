import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../features/activity/domain/activity.dart' show ActivityType;
import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'activity_type_chip.dart';
import 'route_trail_preview.dart';
import 'trail_painter.dart';
import 'user_avatar.dart';

/// The signature card. The walk is the picture; everything else is a caption.
///
/// Deliberately *not* a stat grid: the traced route leads, then one line of
/// who/what/when, then the numbers folded into a single sentence. A card should
/// read like a photograph of the walk, not a dashboard of it.
class PilgrimageCard extends StatelessWidget {
  const PilgrimageCard({
    super.key,
    required this.title,
    required this.type,
    required this.startedAt,
    required this.distanceMeters,
    required this.duration,
    required this.route,
    this.waypoints = const [],
    this.intentions = const [],
    this.authorName,
    this.authorInitials,
    this.authorAccentIndex = 0,
    this.encouragementCount = 0,
    this.commentCount = 0,
    this.encouraged = false,
    this.isSelf = false,
    this.onTap,
    this.onEncourage,
    this.onComment,
    this.onAuthorTap,
  });

  final String title;
  final ActivityType type;
  final DateTime startedAt;
  final double distanceMeters;
  final Duration duration;
  final List<LatLng> route;
  final List<TrailWaypoint> waypoints;

  /// The first two are shown; the rest collapse into "+n more".
  final List<String> intentions;

  /// Null hides the byline — History shows your own walks without repeating
  /// your name on every card.
  final String? authorName;
  final String? authorInitials;
  final int authorAccentIndex;

  final int encouragementCount;
  final int commentCount;
  final bool encouraged;
  final bool isSelf;

  final VoidCallback? onTap;
  final VoidCallback? onEncourage;
  final VoidCallback? onComment;
  final VoidCallback? onAuthorTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final showAuthor = authorName != null;

    final paceLabel = type.usesSpeed
        ? '${Fmt.speed(distanceMeters, duration)} km/h'
        : '${Fmt.pace(distanceMeters, duration)} /km';
    final caption =
        '${Fmt.distance(distanceMeters)}  ·  ${Fmt.duration(duration)}  ·  $paceLabel';

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RouteTrailPreview(
              points: route,
              waypoints: waypoints,
              semanticLabel:
                  '$title. ${Fmt.distance(distanceMeters)} traced route'
                  '${waypoints.isEmpty ? '' : ', ${Fmt.plural(waypoints.length, 'prayer waypoint')}'}',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showAuthor)
                    _Byline(
                      name: authorName!,
                      initials: authorInitials ?? '?',
                      accentIndex: authorAccentIndex,
                      type: type,
                      startedAt: startedAt,
                      isSelf: isSelf,
                      onTap: onAuthorTap,
                    )
                  else
                    Row(
                      children: [
                        ActivityTypeChip(type: type),
                        const SizedBox(width: AppSpacing.sm),
                        // The chip keeps its size; the timestamp gives way at
                        // large text settings rather than the row spilling.
                        Flexible(
                          child: Text(
                            Fmt.relativeTime(startedAt),
                            style: theme.textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: AppSpacing.md),
                  Text(title, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    caption,
                    style: AppTypography.statInline(
                      scheme.onSurfaceVariant,
                    ).copyWith(letterSpacing: 0.1),
                  ),
                  if (intentions.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    _IntentionsPreview(intentions: intentions),
                  ],
                ],
              ),
            ),
            const Divider(indent: AppSpacing.lg, endIndent: AppSpacing.lg),
            _CardActions(
              encouragementCount: encouragementCount,
              commentCount: commentCount,
              encouraged: encouraged,
              onEncourage: onEncourage,
              onComment: onComment,
            ),
          ],
        ),
      ),
    );
  }
}

class _Byline extends StatelessWidget {
  const _Byline({
    required this.name,
    required this.initials,
    required this.accentIndex,
    required this.type,
    required this.startedAt,
    required this.isSelf,
    this.onTap,
  });

  final String name;
  final String initials;
  final int accentIndex;
  final ActivityType type;
  final DateTime startedAt;
  final bool isSelf;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: AppRadius.chip,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxs),
            child: UserAvatar(
              initials: initials,
              accentIndex: accentIndex,
              size: AppSizes.avatarSm,
              ring: isSelf,
              semanticLabel: isSelf ? 'You' : name,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isSelf ? 'You' : name,
                style: theme.textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '${type.gerund} · ${Fmt.relativeTime(startedAt)}',
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        ActivityTypeChip(type: type, compact: true),
      ],
    );
  }
}

class _IntentionsPreview extends StatelessWidget {
  const _IntentionsPreview({required this.intentions});

  final List<String> intentions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = intentions.take(2).toList();
    final remaining = intentions.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final intention in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Icon(
                    Icons.local_fire_department_rounded,
                    size: 14,
                    color: theme.colorScheme.tertiary,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    intention,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (remaining > 0)
          Padding(
            padding: const EdgeInsets.only(left: 22),
            child: Text(
              '+$remaining more ${remaining == 1 ? 'intention' : 'intentions'}',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _CardActions extends StatelessWidget {
  const _CardActions({
    required this.encouragementCount,
    required this.commentCount,
    required this.encouraged,
    this.onEncourage,
    this.onComment,
  });

  final int encouragementCount;
  final int commentCount;
  final bool encouraged;
  final VoidCallback? onEncourage;
  final VoidCallback? onComment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          // Two buttons whose labels grow with the text setting. Loose flex
          // keeps them at their natural size until they would not both fit,
          // then each gives way inside its own half.
          Flexible(
            child: _CardAction(
              icon: encouraged
                  ? Icons.local_fire_department_rounded
                  : Icons.local_fire_department_outlined,
              label: encouragementCount == 0
                  ? 'Encourage'
                  : '$encouragementCount',
              semanticLabel: encouraged
                  ? 'Withdraw encouragement. ${Fmt.plural(encouragementCount, 'encouragement')}'
                  : 'Send encouragement. ${Fmt.plural(encouragementCount, 'encouragement')}',
              color: encouraged ? scheme.tertiary : scheme.onSurfaceVariant,
              onPressed: onEncourage,
            ),
          ),
          Flexible(
            child: _CardAction(
              icon: Icons.mode_comment_outlined,
              label: commentCount == 0 ? 'Comment' : '$commentCount',
              semanticLabel: Fmt.plural(commentCount, 'comment'),
              color: scheme.onSurfaceVariant,
              onPressed: onComment,
            ),
          ),
        ],
      ),
    );
  }
}

class _CardAction extends StatelessWidget {
  const _CardAction({
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.color,
    this.onPressed,
  });

  final IconData icon;
  final String label;
  final String semanticLabel;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20, color: color),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: TextButton.styleFrom(
          foregroundColor: color,
          textStyle: Theme.of(context).textTheme.labelMedium,
        ),
      ),
    );
  }
}
