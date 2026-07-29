import '../../profile/domain/user_profile.dart';

/// One person's worth of data in a list of people.
///
/// The counterpart to `FeedEntry`: what a member looks like on a result row,
/// joined for the viewer. [isFollowing] rides along on the same row so a list of
/// twenty results can offer twenty Follow buttons without twenty more queries —
/// the same N+1 the feed's `activity_card` was shaped to avoid.
class MemberCard {
  const MemberCard({
    required this.profile,
    required this.isFollowing,
    this.followerCount = 0,
    this.lastWalkedAt,
  });

  final UserProfile profile;

  /// Whether the viewer already follows this person.
  final bool isFollowing;

  final int followerCount;

  /// The newest walk of theirs **this viewer may see**, which is not the same
  /// as the newest walk they took. Null for somebody whose walks are all
  /// private or kept to their own followers — the honest answer to "have they
  /// been out lately" from where the viewer is standing, and not a signal that
  /// they have been idle.
  final DateTime? lastWalkedAt;
}
