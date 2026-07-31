import 'package:prayer_walk/src/features/admin/domain/admin_models.dart';
import 'package:prayer_walk/src/features/admin/domain/admin_repository.dart';
import 'package:prayer_walk/src/features/devotionals/domain/devotional.dart';
import 'package:prayer_walk/src/features/devotionals/domain/devotional_repository.dart';
import 'package:prayer_walk/src/features/discovery/domain/discovery_repository.dart';
import 'package:prayer_walk/src/features/discovery/domain/member_card.dart';
import 'package:prayer_walk/src/features/feed/domain/feed_entry.dart';
import 'package:prayer_walk/src/features/feed/domain/feed_repository.dart';
import 'package:prayer_walk/src/features/privacy/domain/activity_visibility.dart';
import 'package:prayer_walk/src/features/privacy/domain/privacy_repository.dart';
import 'package:prayer_walk/src/features/privacy/domain/privacy_zone.dart';
import 'package:prayer_walk/src/features/profile/domain/profile_fields.dart';
import 'package:prayer_walk/src/features/profile/domain/profile_repository.dart';
import 'package:prayer_walk/src/features/profile/domain/user_profile.dart';
import 'package:prayer_walk/src/features/scripture/domain/bible_translation.dart';
import 'package:prayer_walk/src/features/scripture/domain/scripture_library.dart';
import 'package:prayer_walk/src/features/scripture/domain/scripture_prompt.dart';
import 'package:prayer_walk/src/features/scripture/domain/scripture_repository.dart';
import 'package:prayer_walk/src/features/scripture/domain/scripture_submission.dart';
import 'package:prayer_walk/src/features/social/domain/social_repository.dart';

/// Repository doubles for widget tests.
///
/// A widget test has no Supabase, so the app is booted with these overriding
/// the real implementations at the repository seam — the same seam each feature
/// swaps at in `main`. Nothing mock ships in `lib/` any more: every repository
/// there talks to Postgres, and these exist only so a test can pump frames.

class StubFeedRepository implements FeedRepository {
  const StubFeedRepository(this.entries) : exploreOnly = false;

  /// The shape of a brand-new account: it follows nobody and has walked
  /// nowhere, so Following is empty while Explore still has public walks in it.
  /// That combination is the one the empty-feed fix exists for, so a test needs
  /// to be able to produce it.
  const StubFeedRepository.explore(this.entries) : exploreOnly = true;

  final List<FeedEntry> entries;

  /// Whether [feedFor] should come back empty — the shape of a brand-new
  /// account, which follows nobody and has walked nowhere, while Explore still
  /// has public walks in it. That combination is the one the empty-feed fix
  /// exists for, so a test needs to be able to produce it.
  final bool exploreOnly;

  @override
  Future<List<FeedEntry>> feedFor(
    String viewerId, {
    DateTime? before,
    int limit = 50,
  }) async => exploreOnly ? const [] : entries;

  @override
  Future<List<FeedEntry>> exploreFor(
    String viewerId, {
    DateTime? before,
    int limit = 30,
  }) async => exploreOnly ? entries : const [];
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
///
/// [memberRows] and [reportRows] default to empty so a reachability test gets
/// the honest empty states. The responsive suite passes real ones — an empty
/// list cannot overflow, so a layout test that sees no rows is testing nothing.
class StubAdminRepository implements AdminRepository {
  const StubAdminRepository({
    this.memberRows = const [],
    this.reportRows = const [],
    this.announcementRows = const [],
  });

  final List<UserProfile> memberRows;
  final List<ModerationReport> reportRows;
  final List<Announcement> announcementRows;

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
  Future<List<UserProfile>> members(MemberQuery query) async => memberRows;

  @override
  Future<UserProfile> memberById(String id) async => memberRows.firstWhere(
    (m) => m.id == id,
    orElse: () => throw StateError('no member $id'),
  );

  @override
  Future<int> activityCountFor(String userId) async => 42;

  @override
  Future<UserProfile> setRole(String userId, UserRole role) async =>
      throw UnimplementedError();

  @override
  Future<UserProfile> setStatus(String userId, MemberStatus status) async =>
      throw UnimplementedError();

  @override
  Future<List<ModerationReport>> reports({ReportStatus? status}) async =>
      status == null
      ? reportRows
      : reportRows.where((r) => r.status == status).toList();

  @override
  Future<ModerationReport> resolveReport(
    String id,
    ReportStatus outcome,
  ) async => throw UnimplementedError();

  @override
  Future<List<Announcement>> announcements() async => announcementRows;

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

/// One profile in memory, with the writes recorded.
///
/// Holds a real [UserProfile] rather than answering from a fixed literal,
/// because the point of most profile tests is that a write came back changed —
/// a stub that always returns the same person can only prove that nothing
/// threw. [edits] and [uploads] are kept so a test can assert on what was
/// actually sent, not just on what came back.
class StubProfileRepository implements ProfileRepository {
  StubProfileRepository(this.profile);

  UserProfile profile;

  /// Every [ProfileEdit] this has been handed, in order.
  final List<ProfileEdit> edits = [];

  /// Every avatar that reached [uploadAvatar] — including the one that throws,
  /// so a failure test can tell "refused" from "never got there".
  final List<AvatarUpload> uploads = [];

  /// Set to make [uploadAvatar] throw, for the case where a photo fails to
  /// upload and the previous one has to survive it.
  Object? uploadError;

  /// Set to make [updateProfile] throw — a taken handle, most often.
  Object? updateError;

  @override
  Future<UserProfile> profileById(String id) async => profile;

  @override
  Future<UserProfile> updateProfile(String id, ProfileEdit edit) async {
    edits.add(edit);
    final error = updateError;
    if (error != null) throw error;
    profile = profile.copyWith(
      displayName: edit.displayName.trim(),
      handle: canonicalHandle(edit.handle),
      bio: edit.bio.trim(),
      parish: edit.parish.trim(),
      pronouns: edit.pronouns.trim(),
      location: edit.location.trim(),
      links: profileLink(edit.links) ?? '',
    );
    return profile;
  }

  @override
  Future<UserProfile> uploadAvatar(String id, AvatarUpload upload) async {
    uploads.add(upload);
    final error = uploadError;
    // Thrown *after* recording and *before* the profile changes, which is the
    // real repository's ordering too: the row is only re-pointed once the
    // object is written.
    if (error != null) throw error;
    profile = profile.copyWith(
      avatarUrl: 'https://example.test/storage/v1/object/public/avatars/'
          '$id/${uploads.length}.jpg',
    );
    return profile;
  }

  @override
  Future<UserProfile> removeAvatar(String id) async {
    profile = profile.copyWith(avatarUrl: UserProfile.noAvatar);
    return profile;
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

/// The prompt library in memory.
///
/// [publishedPrompts] never throws, matching the contract the real one keeps —
/// a walk must get verses or an empty list, never an exception.
class StubScriptureRepository implements ScriptureRepository {
  StubScriptureRepository([List<ScripturePrompt>? prompts])
    : prompts = prompts ?? defaultPrompts();

  final List<ScripturePrompt> prompts;

  static List<ScripturePrompt> defaultPrompts() => const [
    ScripturePrompt(
      id: 'p_1',
      reference: 'Psalm 121:1-2',
      body:
          'I will lift up my eyes to the hills. Where does my help come from? '
          'My help comes from the LORD, who made heaven and earth.',
      translation: 'WEBBE',
      category: DevotionalCategory.scriptureWalk,
      sortOrder: 10,
    ),
    ScripturePrompt(
      id: 'p_2',
      reference: 'Before the first mile',
      body:
          'Lord, the day is not mine to command. Walk it with me, and let me '
          'notice what you have already put in it.',
      kind: ScripturePromptKind.prayer,
      category: DevotionalCategory.morningLight,
      sortOrder: 20,
      isPublished: false,
    ),
  ];

  @override
  Future<List<ScripturePrompt>> publishedPrompts({
    DevotionalCategory? category,
  }) async => (await publishedLibrary(category: category)).prompts;

  /// An in-memory library reports itself as cached: it is neither a live read
  /// nor the asset in the binary, and claiming either would make the diagnostic
  /// readout lie in the one place a test could not notice.
  @override
  Future<ScriptureLibrary> publishedLibrary({
    DevotionalCategory? category,
  }) async {
    final available = prompts
        .where((p) => p.isPublished)
        .where((p) => category == null || p.category == category)
        .toList();
    return ScriptureLibrary(
      prompts: available,
      source: ScriptureLibrarySource.cache,
      requested: BibleTranslation.fallback,
      available: available,
    );
  }

  @override
  Future<List<ScripturePrompt>> allPrompts() async => List.of(prompts);

  @override
  Future<ScripturePrompt> savePrompt(ScripturePromptDraft draft) async =>
      throw UnimplementedError();

  @override
  Future<ScripturePrompt> setPublished(
    String id, {
    required bool published,
  }) async => throw UnimplementedError();

  @override
  Future<void> deletePrompt(String id) async => throw UnimplementedError();

  // ------------------------------------------------- member contributions ---

  /// Submissions accepted so far, so a test can assert that sending one wrote
  /// something rather than merely not throwing.
  final List<ScriptureSubmissionDraft> submitted = [];

  @override
  Future<void> submitPrompt(ScriptureSubmissionDraft draft) async {
    submitted.add(draft);
  }

  /// One pending suggestion, with a long reflection and a long contributor
  /// name — the row the queue has to fit, and the reason the responsive suite
  /// passes real rows rather than an empty list, which cannot overflow.
  static List<ScriptureSubmission> defaultSubmissions() => [
    ScriptureSubmission(
      prompt: const ScripturePrompt(
        id: 'sub_1',
        reference: '1 Thessalonians 5:16-18',
        body:
            'Always rejoice. Pray without ceasing. In everything give thanks, '
            'for this is the will of God in Christ Jesus toward you.',
        translation: 'WEBBE',
        category: DevotionalCategory.gratitude,
        isPublished: false,
        contributorName: 'Maria Reyes',
      ),
      status: SubmissionStatus.pending,
      contributorId: 'b6f3e1a2-0000-4000-8000-00000000000a',
      contributorName: 'Maria Reyes',
      reflection:
          'I read this on the hill behind the parish the week my father was '
          'in hospital, and it is the only thing I could hold on to for a '
          'while. It belongs on a gratitude walk.',
      submittedAt: DateTime(2026, 7, 27),
    ),
  ];

  final List<ScriptureSubmission> submissionRows = defaultSubmissions();

  @override
  Future<List<ScriptureSubmission>> mySubmissions() async => submissionRows;

  @override
  Future<List<ScriptureSubmission>> submissions({
    SubmissionStatus? status,
  }) async => status == null
      ? submissionRows
      : submissionRows.where((s) => s.status == status).toList();

  @override
  Future<void> reviewSubmission(
    String id, {
    required SubmissionStatus outcome,
    String reason = '',
  }) async => throw UnimplementedError();
}

/// Zones, blocks and the visibility default, in memory.
///
/// Enough for a layout test to pump the safety screens, and enough for a test
/// to assert that a zone was written rather than merely that nothing threw.
class StubPrivacyRepository implements PrivacyRepository {
  StubPrivacyRepository({
    this.zoneRows = const [],
    this.blocked = const [],
    this.standing = ActivityVisibility.followers,
    this.noticeSeen = false,
  });

  final List<PrivacyZone> zoneRows;
  final List<UserProfile> blocked;

  /// The member-level default, which [setDefaultVisibility] moves so a test can
  /// assert that changing it changed something.
  ActivityVisibility standing;
  bool noticeSeen;

  /// Visibility changes applied to individual walks, `(activityId, setting)`.
  final List<(String, ActivityVisibility)> visibilityWrites = [];

  @override
  Future<ActivityVisibility> defaultVisibility() async => standing;

  @override
  Future<void> setDefaultVisibility(ActivityVisibility visibility) async =>
      standing = visibility;

  @override
  Future<bool> publicWalkNoticeSeen() async => noticeSeen;

  @override
  Future<void> markPublicWalkNoticeSeen() async => noticeSeen = true;

  @override
  Future<void> setActivityVisibility(
    String activityId,
    ActivityVisibility visibility,
  ) async => visibilityWrites.add((activityId, visibility));

  @override
  Future<List<PrivacyZone>> zones() async => zoneRows;

  @override
  Future<PrivacyZone> saveZone(PrivacyZoneDraft draft) async =>
      throw UnimplementedError();

  @override
  Future<void> deleteZone(String id) async => throw UnimplementedError();

  @override
  Future<List<UserProfile>> blockedMembers() async => blocked;

  @override
  Future<bool> isBlocked(String otherId) async =>
      blocked.any((p) => p.id == otherId);

  @override
  Future<bool> toggleBlock(String otherId) async =>
      throw UnimplementedError();
}

/// Search results and suggestions, fixed.
class StubDiscoveryRepository implements DiscoveryRepository {
  const StubDiscoveryRepository({
    this.results = const [],
    this.suggestions = const [],
  });

  final List<MemberCard> results;
  final List<MemberCard> suggestions;

  @override
  Future<List<MemberCard>> searchMembers(String query, {int limit = 20}) async =>
      query.trim().isEmpty ? const [] : results;

  @override
  Future<List<MemberCard>> suggestedMembers({int limit = 8}) async =>
      suggestions;
}
