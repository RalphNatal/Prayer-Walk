import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../activity/data/activity_providers.dart';
import '../../auth/data/auth_providers.dart';
import '../../feed/data/feed_providers.dart';
import '../../profile/data/profile_providers.dart';
import 'social_providers.dart';

/// Social mutations, plus the invalidations that keep every surface honest.
///
/// An encouragement shows up on the feed card, the activity detail and the
/// author's counts. Screens should not each have to remember that, so the
/// refresh lives with the write.
///
/// Nothing here swallows a failure: the callers render optimistically and need
/// the exception to know to revert.
class SocialActions {
  SocialActions(this._ref);

  final Ref _ref;

  Future<bool?> toggleEncouragement(String activityId) async {
    final viewerId = _ref.read(currentAuthUserIdProvider);
    if (viewerId == null) return null;

    final nowEncouraged = await _ref
        .read(socialRepositoryProvider)
        .toggleEncouragement(activityId: activityId, viewerId: viewerId);

    _ref
      ..invalidate(feedProvider)
      ..invalidate(activityProvider(activityId))
      ..invalidate(encouragedByProvider(activityId))
      ..invalidate(activitiesForUserProvider)
      ..invalidate(historyProvider);
    return nowEncouraged;
  }

  Future<void> addComment(String activityId, String body) async {
    final authorId = _ref.read(currentAuthUserIdProvider);
    if (authorId == null) return;

    await _ref
        .read(socialRepositoryProvider)
        .addComment(activityId: activityId, authorId: authorId, body: body);

    _ref
      ..invalidate(commentsProvider(activityId))
      ..invalidate(activityProvider(activityId))
      ..invalidate(activitiesForUserProvider)
      ..invalidate(historyProvider)
      ..invalidate(feedProvider);
  }

  Future<bool?> toggleFollow(String otherId) async {
    final viewerId = _ref.read(currentAuthUserIdProvider);
    if (viewerId == null) return null;

    final nowFollowing = await _ref
        .read(socialRepositoryProvider)
        .toggleFollow(viewerId: viewerId, otherId: otherId);

    // Both people's counts move, and so does what the feed is allowed to show.
    _ref
      ..invalidate(isFollowingProvider(otherId))
      ..invalidate(profileProvider(otherId))
      ..invalidate(profileProvider(viewerId))
      ..invalidate(followersProvider(otherId))
      ..invalidate(followingProvider(viewerId))
      ..invalidate(currentProfileProvider)
      ..invalidate(feedProvider);
    return nowFollowing;
  }
}

final socialActionsProvider = Provider<SocialActions>(SocialActions.new);
