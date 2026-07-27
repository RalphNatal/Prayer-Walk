import 'package:prayer_walk/src/features/feed/domain/feed_entry.dart';
import 'package:prayer_walk/src/features/feed/domain/feed_repository.dart';
import 'package:prayer_walk/src/features/profile/domain/user_profile.dart';
import 'package:prayer_walk/src/features/social/domain/social_repository.dart';

/// Repository doubles for widget tests.
///
/// A widget test has no Supabase, so the app is booted with these overriding
/// the real implementations at the repository seam — the same seam the feature
/// swaps at. Nothing mock ships in `lib/` for these features any more.

class StubFeedRepository implements FeedRepository {
  const StubFeedRepository(this.entries);

  final List<FeedEntry> entries;

  @override
  Future<List<FeedEntry>> feedFor(
    String viewerId, {
    DateTime? before,
    int limit = 50,
  }) async => entries;
}

/// A social graph in a map. Enough to satisfy the screens under test, and
/// enough to assert that a toggle is a toggle.
class FakeSocialRepository implements SocialRepository {
  FakeSocialRepository();

  /// `(activityId, viewerId)` pairs that have been encouraged.
  final Set<(String, String)> encouragements = {};

  /// `(followerId, followeeId)` pairs.
  final Set<(String, String)> follows = {};

  final List<({String activityId, String authorId, String body})> comments = [];

  @override
  Future<List<CommentWithAuthor>> commentsFor(String activityId) async => const [];

  @override
  Future<void> addComment({
    required String activityId,
    required String authorId,
    required String body,
  }) async {
    comments.add((activityId: activityId, authorId: authorId, body: body));
  }

  @override
  Future<bool> toggleEncouragement({
    required String activityId,
    required String viewerId,
  }) async {
    final key = (activityId, viewerId);
    if (!encouragements.remove(key)) {
      encouragements.add(key);
      return true;
    }
    return false;
  }

  @override
  Future<List<UserProfile>> encouragedBy(String activityId) async => const [];

  @override
  Future<List<UserProfile>> followers(String userId) async => const [];

  @override
  Future<List<UserProfile>> following(String userId) async => const [];

  @override
  Future<bool> isFollowing({
    required String viewerId,
    required String otherId,
  }) async => follows.contains((viewerId, otherId));

  @override
  Future<bool> toggleFollow({
    required String viewerId,
    required String otherId,
  }) async {
    final key = (viewerId, otherId);
    if (!follows.remove(key)) {
      follows.add(key);
      return true;
    }
    return false;
  }
}

/// Fails every write, so the callers' rollback paths can be exercised.
class FailingSocialRepository extends FakeSocialRepository {
  @override
  Future<bool> toggleEncouragement({
    required String activityId,
    required String viewerId,
  }) async => throw Exception('offline');

  @override
  Future<bool> toggleFollow({
    required String viewerId,
    required String otherId,
  }) async => throw Exception('offline');
}
