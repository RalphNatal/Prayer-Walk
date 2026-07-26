import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../activity/data/mock_activity_repository.dart';
import '../../auth/data/auth_providers.dart';
import '../../feed/data/mock_feed_repository.dart';
import '../../profile/data/mock_profile_repository.dart';
import 'mock_social_repository.dart';

/// Social mutations, plus the invalidations that keep every surface honest.
///
/// An encouragement shows up on the feed card, the activity detail and the
/// author's counts. Screens should not each have to remember that, so the
/// refresh lives with the write.
class SocialActions {
  SocialActions(this._ref);

  final Ref _ref;

  Future<bool?> toggleEncouragement(String activityId) async {
    final viewerId = _ref.read(currentUserIdProvider);
    if (viewerId == null) return null;

    final nowEncouraged = await _ref
        .read(socialRepositoryProvider)
        .toggleEncouragement(activityId: activityId, viewerId: viewerId);

    _ref
      ..invalidate(feedProvider)
      ..invalidate(activityProvider(activityId))
      ..invalidate(encouragedByProvider(activityId))
      ..invalidate(historyProvider);
    return nowEncouraged;
  }

  Future<void> addComment(String activityId, String body) async {
    final authorId = _ref.read(currentUserIdProvider);
    if (authorId == null || body.trim().isEmpty) return;

    await _ref.read(socialRepositoryProvider).addComment(
      activityId: activityId,
      authorId: authorId,
      body: body,
    );

    _ref
      ..invalidate(commentsProvider(activityId))
      ..invalidate(activityProvider(activityId))
      ..invalidate(feedProvider);
  }

  Future<bool?> toggleFollow(String otherId) async {
    final viewerId = _ref.read(currentUserIdProvider);
    if (viewerId == null) return null;

    final nowFollowing = await _ref
        .read(socialRepositoryProvider)
        .toggleFollow(viewerId: viewerId, otherId: otherId);

    _ref
      ..invalidate(isFollowingProvider(otherId))
      ..invalidate(profileProvider(otherId))
      ..invalidate(followersProvider(otherId))
      ..invalidate(followingProvider(viewerId))
      ..invalidate(currentProfileProvider)
      ..invalidate(feedProvider);
    return nowFollowing;
  }
}

final socialActionsProvider = Provider<SocialActions>(SocialActions.new);
