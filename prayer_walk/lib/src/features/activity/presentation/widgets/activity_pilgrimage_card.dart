import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../profile/domain/user_profile.dart';
import '../../../social/data/social_actions.dart';
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
    return PilgrimageCard(
      title: activity.title,
      type: activity.type,
      startedAt: activity.startedAt,
      distanceMeters: activity.distanceMeters,
      duration: activity.duration,
      route: activity.route,
      waypoints: activity.waypoints.toTrailWaypoints(),
      intentions: activity.intentions
          .map((i) => i.text)
          .toList(growable: false),
      authorName: author?.displayName,
      authorInitials: author?.initials,
      authorAccentIndex: author?.accentIndex ?? 0,
      encouragementCount: activity.encouragementCount,
      commentCount: activity.commentCount,
      encouraged: activity.encouragedByViewer,
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
      onEncourage: () =>
          ref.read(socialActionsProvider).toggleEncouragement(activity.id),
      onComment: () => context.pushNamed(
        Routes.activityDetail,
        pathParameters: {'activityId': activity.id},
      ),
    );
  }
}
