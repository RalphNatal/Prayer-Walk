import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../profile/domain/user_profile.dart';
import '../../../social/data/social_actions.dart';
import '../../../social/presentation/optimistic_toggle.dart';
import '../../domain/activity.dart';
import '../trail_mapping.dart';

/// Binds an [Activity] to the shared [PilgrimageCard].
///
/// Feed, history and profile all show the same card; wiring it three times is
/// how the three drift apart.
class ActivityPilgrimageCard extends ConsumerWidget {
  const ActivityPilgrimageCard({
    super.key,
    required this.activity,
    this.author,
    this.isSelf = false,
  });

  final Activity activity;

  /// Null hides the byline — History does not need to tell you who you are.
  final UserProfile? author;
  final bool isSelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The card answers the tap itself and takes it back if the write fails —
    // waiting for the round trip would make every encouragement feel doubtful.
    return OptimisticToggle(
      value: activity.encouragedByViewer,
      onToggle: () =>
          ref.read(socialActionsProvider).toggleEncouragement(activity.id),
      onFailure: (error, stack) => reportFailure(
        context,
        error,
        stack,
        tag: 'PW-CARD',
        fallback: "That encouragement didn't send.",
      ),
      builder: (context, encouraged, delta, toggle) => PilgrimageCard(
        title: activity.title,
        type: activity.type,
        startedAt: activity.startedAt,
        distanceMeters: activity.distanceMeters,
        duration: activity.duration,
        route: activity.route,
        waypoints: activity.waypoints.toTrailWaypoints(Theme.of(context).trail),
        intentions: activity.intentions
            .map((i) => i.text)
            .toList(growable: false),
        authorName: author?.displayName,
        authorInitials: author?.initials,
        authorAccentIndex: author?.accentIndex ?? 0,
        authorAvatarUrl: author?.avatarUrl,
        encouragementCount: activity.encouragementCount + delta,
        commentCount: activity.commentCount,
        encouraged: encouraged,
        isSelf: isSelf,
        onTap: () => context.pushNamed(
          Routes.activityDetail,
          pathParameters: {'activityId': activity.id},
        ),
        onAuthorTap: author == null || isSelf
            ? null
            : () => context.pushNamed(
                Routes.userProfile,
                pathParameters: {'userId': author!.id},
              ),
        onEncourage: toggle,
        onComment: () => context.pushNamed(
          Routes.activityDetail,
          pathParameters: {'activityId': activity.id},
        ),
      ),
    );
  }
}
