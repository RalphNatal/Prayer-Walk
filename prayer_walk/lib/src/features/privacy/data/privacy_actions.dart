import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../activity/data/activity_providers.dart';
import '../../auth/data/auth_providers.dart';
import '../../discovery/data/discovery_providers.dart';
import '../../feed/data/feed_providers.dart' show exploreFeedProvider, feedProvider;
import '../../profile/data/profile_providers.dart';
import '../../social/data/social_providers.dart';
import '../domain/activity_visibility.dart';
import '../domain/privacy_zone.dart';
import 'privacy_providers.dart';

/// Privacy mutations, plus the invalidations that keep every surface honest.
///
/// The same bargain `SocialActions` makes, and here it matters more. Changing a
/// zone changes what strangers receive for *every* walk that passes through it;
/// blocking somebody changes two people's feeds, two profiles and both follow
/// lists at once. A screen that refreshed only itself would leave a route
/// on-screen that the server has already stopped serving, which is the one
/// stale state this feature must never show.
///
/// Nothing swallows a failure: the callers render optimistically or report.
class PrivacyActions {
  PrivacyActions(this._ref);

  final Ref _ref;

  // ------------------------------------------------------------ visibility ---

  Future<void> setDefaultVisibility(ActivityVisibility visibility) async {
    await _ref
        .read(privacyRepositoryProvider)
        .setDefaultVisibility(visibility);
    _ref.invalidate(defaultVisibilityProvider);
  }

  Future<void> setActivityVisibility(
    String activityId,
    ActivityVisibility visibility,
  ) async {
    await _ref
        .read(privacyRepositoryProvider)
        .setActivityVisibility(activityId, visibility);

    // Everywhere the walk can appear, plus Explore — which is precisely the
    // surface a walk joins or leaves when this changes.
    _ref
      ..invalidate(activityProvider(activityId))
      ..invalidate(historyProvider)
      ..invalidate(activitiesForUserProvider)
      ..invalidate(feedProvider)
      ..invalidate(exploreFeedProvider);
  }

  Future<void> markPublicNoticeSeen() async {
    await _ref.read(privacyRepositoryProvider).markPublicWalkNoticeSeen();
    _ref.invalidate(publicWalkNoticeSeenProvider);
  }

  // ----------------------------------------------------------------- zones ---

  Future<void> saveZone(PrivacyZoneDraft draft) async {
    await _ref.read(privacyRepositoryProvider).saveZone(draft);
    _refreshTraces();
  }

  Future<void> deleteZone(String id) async {
    await _ref.read(privacyRepositoryProvider).deleteZone(id);
    _refreshTraces();
  }

  /// Every read that carries route coordinates. A zone is applied server-side
  /// when a walk is *served*, so an already-fetched card in memory is the one
  /// copy in the world still holding the untrimmed line.
  void _refreshTraces() {
    _ref
      ..invalidate(privacyZonesProvider)
      ..invalidate(feedProvider)
      ..invalidate(exploreFeedProvider)
      ..invalidate(historyProvider)
      ..invalidate(activitiesForUserProvider)
      ..invalidate(activityProvider);
  }

  // ---------------------------------------------------------------- blocks ---

  /// Blocks or unblocks. Returns whether [otherId] is now blocked.
  Future<bool?> toggleBlock(String otherId) async {
    final viewerId = _ref.read(currentAuthUserIdProvider);
    if (viewerId == null) return null;

    final nowBlocked = await _ref
        .read(privacyRepositoryProvider)
        .toggleBlock(otherId);

    // A block severs the follow in both directions — by a trigger on `blocks`,
    // so it has already happened by the time this returns. Both people's
    // counts, both follow lists and both feeds move with it.
    _ref
      ..invalidate(isBlockedProvider(otherId))
      ..invalidate(blockedMembersProvider)
      ..invalidate(isFollowingProvider(otherId))
      ..invalidate(profileProvider(otherId))
      ..invalidate(profileProvider(viewerId))
      ..invalidate(currentProfileProvider)
      ..invalidate(followersProvider(otherId))
      ..invalidate(followersProvider(viewerId))
      ..invalidate(followingProvider(otherId))
      ..invalidate(followingProvider(viewerId))
      ..invalidate(activitiesForUserProvider(otherId))
      ..invalidate(feedProvider)
      ..invalidate(exploreFeedProvider)
      ..invalidate(suggestedMembersProvider)
      ..invalidate(memberSearchProvider);
    return nowBlocked;
  }
}

final privacyActionsProvider = Provider<PrivacyActions>(PrivacyActions.new);
