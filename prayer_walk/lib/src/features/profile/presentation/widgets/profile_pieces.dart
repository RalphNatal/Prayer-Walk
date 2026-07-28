import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../activity/data/activity_providers.dart';
import '../../../activity/domain/activity.dart';
import '../../../activity/presentation/trail_mapping.dart';
import '../../domain/user_profile.dart';

/// Avatar, name, parish, bio, and the follow counts.
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({super.key, required this.profile, this.isSelf = false});

  final UserProfile profile;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UserAvatar(
              initials: profile.initials,
              accentIndex: profile.accentIndex,
              size: AppSizes.avatarLg,
              ring: isSelf,
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.displayName,
                    style: theme.textTheme.displaySmall,
                  ),
                  Text(profile.handle, style: theme.textTheme.bodyMedium),
                  if (profile.parish.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Icon(
                          Icons.place_outlined,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            profile.parish,
                            style: theme.textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (profile.bio.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(profile.bio, style: theme.textTheme.bodyLarge),
        ],
        const SizedBox(height: AppSpacing.lg),
        // Two counts with their words spelled out are wider than a narrow
        // phone at a large text setting. They stack rather than spill.
        Wrap(
          spacing: AppSpacing.xl,
          runSpacing: AppSpacing.xs,
          children: [
            _FollowCount(
              count: profile.followerCount,
              label: 'Followers',
              onTap: () => context.pushNamed(
                Routes.followers,
                pathParameters: {'userId': profile.id},
              ),
            ),
            _FollowCount(
              count: profile.followingCount,
              label: 'Following',
              onTap: () => context.pushNamed(
                Routes.following,
                pathParameters: {'userId': profile.id},
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FollowCount extends StatelessWidget {
  const _FollowCount({
    required this.count,
    required this.label,
    required this.onTap,
  });

  final int count;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: '$count $label',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.control,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                Fmt.count(count),
                maxLines: 1,
                style: AppTypography.statInline(
                  theme.colorScheme.onSurface,
                  size: 16,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lifetime totals — the four numbers a walker actually checks.
class LifetimeStatsPanel extends StatelessWidget {
  const LifetimeStatsPanel({super.key, required this.stats});

  final LifetimeStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.card,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatStrip(
            children: [
              StatTile(
                label: 'Distance',
                value: (stats.totalDistanceMeters / 1000).round().toString(),
                unit: 'km',
              ),
              StatTile(
                label: 'Time',
                value: stats.totalDuration.inHours.toString(),
                unit: 'h',
              ),
              StatTile(
                label: 'Walks',
                value: stats.activityCount.toString(),
              ),
              StatTile(
                label: 'Streak',
                value: stats.streakDays.toString(),
                unit: 'd',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '${Fmt.plural(stats.intentionCount, 'intention')} carried so far.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// A horizontal strip of recent walks, each led by its trail.
class RecentActivitiesStrip extends ConsumerWidget {
  const RecentActivitiesStrip({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activities = ref.watch(activitiesForUserProvider(userId));

    return AsyncView<List<Activity>>(
      value: activities,
      errorFallback: "Recent walks couldn't be loaded.",
      onRetry: () => ref.invalidate(activitiesForUserProvider(userId)),
      isEmpty: (items) => items.isEmpty,
      // Same 178 height and the same horizontally-scrolling shape as the data
      // state below, so there is no jump between them — and, because the Row
      // sits in a scroll view, no RenderFlex overflow on a narrow phone. Two
      // 200px cards plus their gap is 412px, which is wider than a 360dp
      // screen. Not draggable: it is a placeholder, not content.
      loading: const SizedBox(
        height: 178,
        child: ShimmerScope(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: NeverScrollableScrollPhysics(),
            child: Row(
              children: [
                SizedBox(width: 200, child: SkeletonBox(height: 168)),
                SizedBox(width: AppSpacing.md),
                SizedBox(width: 200, child: SkeletonBox(height: 168)),
              ],
            ),
          ),
        ),
      ),
      empty: () => Text(
        'No walks recorded yet.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      data: (items) => SizedBox(
        height: 178,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
          itemBuilder: (context, index) =>
              _MiniActivityCard(activity: items[index]),
        ),
      ),
    );
  }
}

class _MiniActivityCard extends StatelessWidget {
  const _MiniActivityCard({required this.activity});

  final Activity activity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 200,
      child: Card(
        child: InkWell(
          onTap: () => context.pushNamed(
            Routes.activityDetail,
            pathParameters: {'activityId': activity.id},
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RouteTrailPreview(
                points: activity.route,
                waypoints: activity.waypoints.toTrailWaypoints(theme.trail),
                height: 100,
                strokeWidth: 3,
                showGlow: false,
                padding: const EdgeInsets.all(12),
                semanticLabel: '${activity.title}, traced route',
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activity.title,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${Fmt.distance(activity.distanceMeters)} · '
                      '${Fmt.relativeTime(activity.startedAt)}',
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
