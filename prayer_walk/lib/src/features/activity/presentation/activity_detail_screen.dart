import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/data/auth_providers.dart';
import '../../feed/data/mock_feed_repository.dart';
import '../../profile/data/mock_profile_repository.dart';
import '../../profile/domain/user_profile.dart';
import '../../social/data/mock_social_repository.dart';
import '../../social/data/social_actions.dart';
import '../../social/domain/social_repository.dart';
import '../data/mock_activity_repository.dart';
import '../domain/activity.dart';
import 'trail_mapping.dart';

/// One walk, in full: the trail, the numbers, what was carried, who responded.
class ActivityDetailScreen extends ConsumerWidget {
  const ActivityDetailScreen({super.key, required this.activityId});

  final String activityId;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete this walk?',
      message:
          'The route, the intentions and every comment on it are removed. '
          'This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    await ref.read(activityRepositoryProvider).deleteActivity(activityId);
    ref
      ..invalidate(historyProvider)
      ..invalidate(feedProvider)
      ..invalidate(currentProfileProvider);
    if (context.mounted) {
      showAppSnackBar(context, 'Walk deleted.');
      context.canPop() ? context.pop() : context.goNamed(Routes.history);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(activityProvider(activityId));
    final viewerId = ref.watch(currentUserIdProvider);

    return Scaffold(
      body: AsyncView<Activity>(
        value: activity,
        onRetry: () => ref.invalidate(activityProvider(activityId)),
        loading: const _DetailLoading(),
        data: (item) => _DetailBody(
          activity: item,
          isOwn: item.userId == viewerId,
          onDelete: () => _delete(context, ref),
        ),
      ),
    );
  }
}

class _DetailLoading extends StatelessWidget {
  const _DetailLoading();

  @override
  Widget build(BuildContext context) {
    return const ShimmerScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(height: 300, radius: 0),
          Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(height: 26, width: 220),
                SizedBox(height: AppSpacing.md),
                SkeletonBox.line(width: 160),
                SizedBox(height: AppSpacing.xl),
                SkeletonBox(height: 56),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailBody extends ConsumerStatefulWidget {
  const _DetailBody({
    required this.activity,
    required this.isOwn,
    required this.onDelete,
  });

  final Activity activity;
  final bool isOwn;
  final VoidCallback onDelete;

  @override
  ConsumerState<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends ConsumerState<_DetailBody> {
  final _comment = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _comment.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref.read(socialActionsProvider).addComment(widget.activity.id, body);
      _comment.clear();
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          "That comment didn't post. Check your connection, then try again.",
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activity = widget.activity;
    final author = ref.watch(profileProvider(activity.userId));
    final comments = ref.watch(commentsProvider(activity.id));
    final encouragers = ref.watch(encouragedByProvider(activity.id));

    final paceValue = activity.type.usesSpeed
        ? Fmt.speed(activity.distanceMeters, activity.duration)
        : Fmt.pace(activity.distanceMeters, activity.duration);

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 320,
          actions: [
            if (widget.isOwn)
              PopupMenuButton<String>(
                tooltip: 'More actions',
                onSelected: (value) {
                  if (value == 'delete') widget.onDelete();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'delete', child: Text('Delete walk')),
                ],
              ),
            const SizedBox(width: AppSpacing.xs),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: RouteMapView(
              points: activity.route,
              waypoints: activity.waypoints.toTrailWaypoints(),
              interactive: false,
              semanticLabel:
                  '${activity.title}. Traced route of '
                  '${Fmt.distance(activity.distanceMeters)}'
                  '${activity.waypoints.isEmpty ? '' : ' with ${Fmt.plural(activity.waypoints.length, 'prayer waypoint')}'}',
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xxxl,
          ),
          sliver: SliverList.list(
            children: [
              _AuthorRow(author: author, activity: activity, isOwn: widget.isOwn),
              const SizedBox(height: AppSpacing.lg),
              Text(activity.title, style: theme.textTheme.displaySmall),
              const SizedBox(height: AppSpacing.xs),
              Text(
                Fmt.dayAndTime(activity.startedAt),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xl),

              StatStrip(
                children: [
                  StatTile(
                    label: 'Distance',
                    value: Fmt.distanceValue(activity.distanceMeters),
                    unit: Fmt.distanceUnit(activity.distanceMeters),
                  ),
                  StatTile(label: 'Time', value: Fmt.duration(activity.duration)),
                  StatTile(
                    label: activity.type.usesSpeed ? 'Speed' : 'Pace',
                    value: paceValue,
                    unit: activity.type.usesSpeed ? 'km/h' : '/km',
                  ),
                  StatTile(
                    label: 'Climb',
                    value: activity.elevationGainMeters.round().toString(),
                    unit: 'm',
                  ),
                ],
              ),

              if (activity.note.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xl),
                Text(activity.note, style: theme.textTheme.bodyLarge),
              ],

              if (activity.intentions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xxl),
                const SectionHeader(title: 'Carried on this walk'),
                for (final intention in activity.intentions)
                  _IntentionRow(intention: intention),
              ],

              if (activity.waypoints.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xxl),
                SectionHeader(
                  title: 'Prayer waypoints',
                  subtitle: Fmt.plural(activity.waypoints.length, 'stop'),
                ),
                for (final waypoint in activity.waypoints)
                  _WaypointTile(waypoint: waypoint),
              ],

              const SizedBox(height: AppSpacing.xxl),
              _EncouragementBar(
                activity: activity,
                encouragers: encouragers,
              ),

              const SizedBox(height: AppSpacing.xxl),
              SectionHeader(
                title: 'Comments',
                subtitle: Fmt.plural(activity.commentCount, 'comment'),
              ),
              AsyncView<List<CommentWithAuthor>>(
                value: comments,
                onRetry: () => ref.invalidate(commentsProvider(activity.id)),
                isEmpty: (items) => items.isEmpty,
                loading: const RowListLoading(count: 2, leadingSize: 32),
                empty: () => Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Text(
                    'No comments yet. Say something to whoever walked this.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                data: (items) => Column(
                  children: [
                    for (final entry in items) _CommentTile(entry: entry),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _CommentComposer(
                controller: _comment,
                sending: _sending,
                onSend: _send,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AuthorRow extends StatelessWidget {
  const _AuthorRow({
    required this.author,
    required this.activity,
    required this.isOwn,
  });

  final AsyncValue<UserProfile> author;
  final Activity activity;
  final bool isOwn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AsyncView<UserProfile>(
      value: author,
      loading: const ShimmerScope(child: ListRowSkeleton(leadingSize: 44)),
      data: (profile) => Row(
        children: [
          UserAvatar(
            initials: profile.initials,
            accentIndex: profile.accentIndex,
            ring: isOwn,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isOwn ? 'You' : profile.displayName,
                  style: theme.textTheme.titleSmall,
                ),
                Text(
                  '${activity.type.gerund} · ${Fmt.relativeTime(activity.startedAt)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (!isOwn)
            SecondaryButton(
              label: 'View profile',
              onPressed: () => context.pushNamed(
                Routes.userProfile,
                pathParameters: {'userId': profile.id},
              ),
            ),
        ],
      ),
    );
  }
}

class _IntentionRow extends StatelessWidget {
  const _IntentionRow({required this.intention});

  final PrayerIntention intention;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.local_fire_department_rounded,
              size: 18,
              color: theme.colorScheme.tertiary,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(intention.text, style: theme.textTheme.bodyLarge),
                Text(
                  intention.category.label,
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WaypointTile extends StatelessWidget {
  const _WaypointTile({required this.waypoint});

  final Waypoint waypoint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(top: 5, right: AppSpacing.md),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.tertiary,
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.tertiary.withValues(alpha: 0.55),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(waypoint.label, style: theme.textTheme.titleSmall),
                Text(
                  '${waypoint.kind.label}  ·  ${Fmt.durationShort(waypoint.elapsed)} in',
                  style: theme.textTheme.bodySmall,
                ),
                if (waypoint.note.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(waypoint.note, style: theme.textTheme.bodyMedium),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EncouragementBar extends ConsumerWidget {
  const _EncouragementBar({required this.activity, required this.encouragers});

  final Activity activity;
  final AsyncValue<List<UserProfile>> encouragers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final people = encouragers.value ?? const <UserProfile>[];

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
          Row(
            children: [
              Expanded(
                child: Text(
                  activity.encouragementCount == 0
                      ? 'No encouragement yet'
                      : Fmt.plural(
                          activity.encouragementCount,
                          'encouragement',
                        ),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              PrimaryButton(
                label: activity.encouragedByViewer ? 'Sent' : 'Send encouragement',
                icon: activity.encouragedByViewer
                    ? Icons.check_rounded
                    : Icons.local_fire_department_rounded,
                onPressed: () => ref
                    .read(socialActionsProvider)
                    .toggleEncouragement(activity.id),
              ),
            ],
          ),
          if (people.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final person in people)
                  UserAvatar(
                    initials: person.initials,
                    accentIndex: person.accentIndex,
                    size: AppSizes.avatarSm,
                    semanticLabel: '${person.displayName} sent encouragement',
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.entry});

  final CommentWithAuthor entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(
            initials: entry.author.initials,
            accentIndex: entry.author.accentIndex,
            size: AppSizes.avatarSm,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.author.displayName,
                        style: theme.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      Fmt.relativeTime(entry.comment.createdAt),
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(entry.comment.body, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentComposer extends StatelessWidget {
  const _CommentComposer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
            decoration: const InputDecoration(
              hintText: 'Say something',
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          height: 56,
          child: PrimaryButton(
            label: 'Post',
            busy: sending,
            onPressed: onSend,
            semanticLabel: 'Post comment',
          ),
        ),
      ],
    );
  }
}
