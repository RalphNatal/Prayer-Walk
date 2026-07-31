import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
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
import '../../domain/profile_fields.dart';
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
              imageUrl: profile.avatarUrl,
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
                  // Handle and pronouns on one line, wrapping rather than
                  // ellipsing: a pronoun set that gets cut in half is worse
                  // than one that takes a second line.
                  Wrap(
                    spacing: AppSpacing.sm,
                    children: [
                      Text(profile.handle, style: theme.textTheme.bodyMedium),
                      if (profile.pronouns.isNotEmpty)
                        Text(
                          profile.pronouns,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  if (profile.parish.isNotEmpty)
                    _HeaderDetail(
                      icon: Icons.church_outlined,
                      text: profile.parish,
                    ),
                  if (profile.location.isNotEmpty)
                    _HeaderDetail(
                      icon: Icons.place_outlined,
                      text: profile.location,
                    ),
                ],
              ),
            ),
          ],
        ),
        if (profile.bio.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(profile.bio, style: theme.textTheme.bodyLarge),
        ],
        if (profile.links.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _ProfileLink(url: profile.links),
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

/// One icon-and-text line under the name — parish, or location.
class _HeaderDetail extends StatelessWidget {
  const _HeaderDetail({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// A member's own link, shown as text and copyable — never opened in the app.
///
/// This is deliberately not a tappable link, and the reason is the guardrail
/// rather than laziness: a member-supplied URL opened in an in-app webview runs
/// inside this app's session and chrome, which is how a page nobody vetted gets
/// to look like part of Prayer Walk. The two honest options were plain text or
/// a hand-off to the system browser, and plain text needs no new dependency and
/// no `queries` entry in the manifest to work on Android 11+.
///
/// Tapping copies rather than navigates, so the affordance still does
/// something: someone can paste it into the browser they already trust. The URL
/// is re-checked here even though it was validated before it was stored — the
/// row may have been written by an older build, and this is the last point
/// before it reaches a person.
class _ProfileLink extends StatelessWidget {
  const _ProfileLink({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final safe = profileLink(url);
    if (safe == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return InkWell(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: safe));
        if (context.mounted) showAppSnackBar(context, 'Link copied.');
      },
      borderRadius: AppRadius.control,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.link,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                // The scheme is noise on a profile; what someone reads is the
                // host and path.
                safe.replaceFirst(RegExp(r'^https?://'), ''),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
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
