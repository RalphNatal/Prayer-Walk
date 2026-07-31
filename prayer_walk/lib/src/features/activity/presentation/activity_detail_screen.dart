import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../admin/domain/admin_models.dart' show ReportTargetType;
import '../../auth/data/auth_providers.dart';
import '../../feed/data/feed_providers.dart';
import '../../moderation/presentation/report_sheet.dart';
import '../../privacy/data/privacy_actions.dart';
import '../../privacy/presentation/visibility_picker.dart';
import '../../profile/data/profile_providers.dart';
import '../../profile/domain/user_profile.dart';
import '../../scripture/data/scripture_providers.dart'
    show scriptureSettingsProvider;
import '../../scripture/presentation/scripture_quotation.dart';
import '../../social/data/social_actions.dart';
import '../../social/data/social_providers.dart';
import '../../social/data/supabase_social_repository.dart' show SocialFailure;
import '../../social/domain/social_repository.dart';
import '../../social/presentation/optimistic_toggle.dart';
import '../data/activity_providers.dart';
import '../domain/activity.dart';
import 'trail_mapping.dart';

/// Log tag for this screen's failures.
const _tag = 'PW-DETAIL';

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

    try {
      await ref.read(activityRepositoryProvider).deleteActivity(activityId);
    } catch (error, stack) {
      // A delete that fails leaves the walk on screen; say which failure it
      // was rather than letting it fall through to the app-wide handler.
      if (context.mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: "The walk wasn't deleted.",
        );
      }
      return;
    }
    ref
      ..invalidate(historyProvider)
      ..invalidate(activitiesForUserProvider)
      ..invalidate(feedProvider);
    if (context.mounted) {
      showAppSnackBar(context, 'Walk deleted.');
      context.canPop() ? context.pop() : context.goNamed(Routes.history);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(activityProvider(activityId));
    final viewerId = ref.watch(currentAuthUserIdProvider);

    return Scaffold(
      body: AsyncView<Activity>(
        value: activity,
        errorFallback: "This walk couldn't be loaded.",
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

  Future<void> _changeVisibility() async {
    final chosen = await showVisibilitySheet(
      context,
      current: widget.activity.visibility,
    );
    if (chosen == null || chosen == widget.activity.visibility) return;
    if (!mounted) return;

    try {
      await ref
          .read(privacyActionsProvider)
          .setActivityVisibility(widget.activity.id, chosen);
    } catch (error, stack) {
      if (mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: "That didn't change.",
        );
      }
      return;
    }
    if (mounted) {
      showAppSnackBar(
        context,
        'This walk is now visible to ${chosen.label.toLowerCase()}.',
      );
    }
  }

  Future<void> _send() async {
    final body = _comment.text.trim();
    if (body.isEmpty) {
      showAppSnackBar(context, 'Write something first.');
      return;
    }
    setState(() => _sending = true);
    try {
      await ref.read(socialActionsProvider).addComment(widget.activity.id, body);
      _comment.clear();
    } on SocialFailure catch (failure, stack) {
      // Already phrased for the person — say what it says, but never silently:
      // a phrased failure is still a failure worth having on the console.
      AppLogger.warn(_tag, 'SocialFailure: ${failure.message}', failure, stack);
      if (mounted) showAppSnackBar(context, failure.message);
    } catch (error, stack) {
      if (mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: "That comment didn't post.",
          onRetry: _send,
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
            // Your own walk offers Delete; someone else's offers Report. There
            // is no case for both — you cannot report yourself, and you cannot
            // delete another person's walk.
            PopupMenuButton<String>(
              tooltip: 'More actions',
              onSelected: (value) => switch (value) {
                'delete' => widget.onDelete(),
                'report' => showReportSheet(
                  context,
                  ref,
                  targetType: ReportTargetType.activity,
                  targetId: activity.id,
                ),
                _ => null,
              },
              itemBuilder: (context) => [
                if (widget.isOwn)
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete walk'),
                  )
                else
                  const PopupMenuItem(
                    value: 'report',
                    child: Text('Report walk'),
                  ),
              ],
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: RouteMapView(
              points: activity.route,
              waypoints: activity.waypoints.toTrailWaypoints(theme.trail),
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
              Row(
                children: [
                  // The date gives way before the place does: a long place name
                  // is the more useful half of this line, and at a large text
                  // setting the two together are wider than a phone.
                  Flexible(
                    child: Text(
                      Fmt.dayAndTime(activity.startedAt),
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Null for older walks, routeless logs and failed lookups —
                  // the line simply reads as it always did.
                  if (activity.placeName != null) ...[
                    Text('  ·  ', style: theme.textTheme.bodySmall),
                    Icon(
                      Icons.place_outlined,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Flexible(
                      child: Text(
                        activity.placeName!,
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
              // Who this walk is for, and — when the server shortened the line
              // before sending it — why the map and the distance disagree.
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  VisibilityChip(
                    visibility: activity.visibility,
                    // Only its owner may change it, and only its owner is shown
                    // the affordance. The update policy is the actual boundary.
                    onTap: widget.isOwn ? () => _changeVisibility() : null,
                  ),
                ],
              ),
              if (activity.routeTrimmed) ...[
                const SizedBox(height: AppSpacing.md),
                const _TrimmedRouteNote(),
              ],
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
                errorFallback: "Comments couldn't be loaded.",
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
      errorFallback: "That walker's name couldn't be loaded.",
      loading: const ShimmerScope(child: ListRowSkeleton(leadingSize: 44)),
      data: (profile) => Row(
        children: [
          UserAvatar(
            initials: profile.initials,
            accentIndex: profile.accentIndex,
            imageUrl: profile.avatarUrl,
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

/// B3 · Why the line is shorter than the walk.
///
/// The server dropped the points at either end of this trace that fell inside
/// one of the walker's privacy zones, before any of it was serialised. The
/// distance above is deliberately *not* recomputed to match — it is the full
/// recorded walk — so the two disagree, and the honest thing is to say why
/// rather than let a viewer notice a 4 km number over a 3 km line and conclude
/// the app cannot count.
///
/// Never shown to the owner, who receives their whole route and for whom
/// `route_trimmed` is always false.
class _TrimmedRouteNote extends StatelessWidget {
  const _TrimmedRouteNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: AppRadius.control,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.shield_outlined,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Part of this route is hidden by a privacy zone. The distance '
              'and time are the full walk.',
              style: theme.textTheme.bodySmall,
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

class _WaypointTile extends ConsumerWidget {
  const _WaypointTile({required this.waypoint});

  final Waypoint waypoint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Matches the cooler marker a verse gets on the trail.
    final tint = waypoint.kind == WaypointKind.scripture
        ? theme.colorScheme.secondary
        : theme.colorScheme.tertiary;
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
              color: tint,
              boxShadow: [
                BoxShadow(
                  color: tint.withValues(alpha: 0.55),
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
                // Same seam the summary list uses: the note carries whatever
                // mark its edition required, and [MarkedQuotation] reads it
                // back and names the edition underneath. See the summary
                // screen's row for why a bare Text is not enough here.
                if (waypoint.note.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  MarkedQuotation(
                    markedText: waypoint.note,
                    style: theme.textTheme.bodyMedium,
                    showTranslation: ref.watch(
                      scriptureSettingsProvider.select((s) => s.showTranslation),
                    ),
                  ),
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
          OptimisticToggle(
            value: activity.encouragedByViewer,
            onToggle: () =>
                ref.read(socialActionsProvider).toggleEncouragement(activity.id),
            onFailure: (error, stack) => reportFailure(
              context,
              error,
              stack,
              tag: _tag,
              fallback: "That encouragement didn't send.",
            ),
            builder: (context, encouraged, delta, toggle) {
              final count = activity.encouragementCount + delta;
              // "Send encouragement" plus its icon is wider than the card on a
              // phone, so the count and the button cannot share a line there.
              // A Wrap keeps them side by side wherever they fit and drops the
              // button beneath the count where they do not — the label stays
              // whole either way.
              return Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    count == 0
                        ? 'No encouragement yet'
                        : Fmt.plural(count, 'encouragement'),
                    style: theme.textTheme.titleSmall,
                  ),
                  Kindle(
                    lit: encouraged,
                    child: PrimaryButton(
                      label: encouraged ? 'Sent' : 'Send encouragement',
                      icon: encouraged
                          ? Icons.check_rounded
                          : Icons.local_fire_department_rounded,
                      onPressed: toggle,
                    ),
                  ),
                ],
              );
            },
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
                    imageUrl: person.avatarUrl,
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

class _CommentTile extends ConsumerWidget {
  const _CommentTile({required this.entry});

  final CommentWithAuthor entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isMine = entry.author.id == ref.watch(currentAuthUserIdProvider);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(
            initials: entry.author.initials,
            accentIndex: entry.author.accentIndex,
            imageUrl: entry.author.avatarUrl,
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
          // Small and unlabelled: an obvious Report button beside every comment
          // changes how a comment thread reads. It is reachable, not loud.
          //
          // The *icon* is small; the button is not. `visualDensity.compact`
          // would take the target down to 40dp, and a quiet affordance is not a
          // reason to put one below the 48dp floor.
          if (!isMine)
            IconButton(
              icon: const Icon(Icons.flag_outlined, size: 18),
              tooltip: 'Report comment',
              color: theme.colorScheme.onSurfaceVariant,
              onPressed: () => showReportSheet(
                context,
                ref,
                targetType: ReportTargetType.comment,
                targetId: entry.comment.id,
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
