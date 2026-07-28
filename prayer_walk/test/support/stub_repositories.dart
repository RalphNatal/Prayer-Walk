import 'package:prayer_walk/src/features/admin/domain/admin_models.dart';
import 'package:prayer_walk/src/features/admin/domain/admin_repository.dart';
import 'package:prayer_walk/src/features/devotionals/domain/devotional.dart';
import 'package:prayer_walk/src/features/devotionals/domain/devotional_repository.dart';
import 'package:prayer_walk/src/features/feed/domain/feed_entry.dart';
import 'package:prayer_walk/src/features/feed/domain/feed_repository.dart';
import 'package:prayer_walk/src/features/profile/domain/user_profile.dart';
import 'package:prayer_walk/src/features/social/domain/social_repository.dart';

/// Repository doubles for widget tests.
///
/// A widget test has no Supabase, so the app is booted with these overriding
/// the real implementations at the repository seam — the same seam each feature
/// swaps at in `main`. Nothing mock ships in `lib/` any more: every repository
/// there talks to Postgres, and these exist only so a test can pump frames.

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

/// A small shelf in memory: one published devotional and one draft, which is
/// what the member browse list and the admin content list each need to render
/// something recognisable.
class StubDevotionalRepository implements DevotionalRepository {
  StubDevotionalRepository([List<Devotional>? shelf])
    : shelf = shelf ?? defaultShelf();

  final List<Devotional> shelf;

  static List<Devotional> defaultShelf() {
    final now = DateTime.now();
    return [
      Devotional(
        id: 'd_1',
        title: 'Before the street wakes',
        summary: 'A short prayer for the first hundred steps of the day.',
        body:
            'Begin before you have decided anything.\n\n'
            'Notice the sound your feet make.',
        scriptureRef: 'Lamentations 3:22-23',
        scriptureText:
            "It is because of the LORD's loving kindnesses that we are not "
            'consumed. They are new every morning.',
        category: DevotionalCategory.morningLight,
        authorName: 'Prayer Walk',
        updatedAt: now.subtract(const Duration(days: 21)),
        publishedAt: now.subtract(const Duration(days: 21)),
        isPublished: true,
        readMinutes: 2,
      ),
      Devotional(
        id: 'd_2',
        title: 'Walking the novena',
        summary: 'Nine days, nine routes, one request.',
        body: 'Draft — needs the nine daily prompts written out.',
        category: DevotionalCategory.intercession,
        authorName: 'Prayer Walk',
        updatedAt: now.subtract(const Duration(days: 1)),
        isPublished: false,
        readMinutes: 5,
      ),
    ];
  }

  @override
  Future<List<Devotional>> published({DevotionalCategory? category}) async =>
      shelf
          .where((d) => d.isPublished)
          .where((d) => category == null || d.category == category)
          .toList();

  @override
  Future<List<Devotional>> all() async => List.of(shelf);

  @override
  Future<Devotional> byId(String id) async => shelf.firstWhere(
    (d) => d.id == id,
    orElse: () => throw StateError('no devotional $id'),
  );

  @override
  Future<Devotional> save(
    DevotionalDraft draft, {
    required String authorName,
  }) async => throw UnimplementedError();

  @override
  Future<Devotional> setPublished(String id, {required bool published}) async =>
      throw UnimplementedError();

  @override
  Future<void> delete(String id) async => throw UnimplementedError();
}

/// Enough of the console to render its screens. The reads answer; the writes
/// throw, because no test drives one and a silent no-op would be the wrong
/// thing to discover later.
class StubAdminRepository implements AdminRepository {
  const StubAdminRepository();

  @override
  Future<AdminMetrics> metrics() async {
    final today = DateTime.now();
    return AdminMetrics(
      totalMembers: 8,
      activeThisWeek: 3,
      activitiesLogged: 12,
      devotionalsPublished: 1,
      activitySeries: [
        for (var i = 13; i >= 0; i--)
          DailyCount(date: today.subtract(Duration(days: i)), count: i % 4),
      ],
      recentSignups: const [],
    );
  }

  @override
  Future<List<UserProfile>> members(MemberQuery query) async => const [];

  @override
  Future<UserProfile> memberById(String id) async =>
      throw UnimplementedError();

  @override
  Future<int> activityCountFor(String userId) async => 0;

  @override
  Future<UserProfile> setRole(String userId, UserRole role) async =>
      throw UnimplementedError();

  @override
  Future<UserProfile> setStatus(String userId, MemberStatus status) async =>
      throw UnimplementedError();

  @override
  Future<List<ModerationReport>> reports({ReportStatus? status}) async =>
      const [];

  @override
  Future<ModerationReport> resolveReport(
    String id,
    ReportStatus outcome,
  ) async => throw UnimplementedError();

  @override
  Future<List<Announcement>> announcements() async => const [];

  @override
  Future<Announcement> sendAnnouncement({
    required String title,
    required String body,
    required AnnouncementAudience audience,
    required String sentByName,
  }) async => throw UnimplementedError();

  @override
  Future<int> audienceSize(AnnouncementAudience audience) async => 0;
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
