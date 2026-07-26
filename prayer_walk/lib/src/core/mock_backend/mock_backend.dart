import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/activity/domain/activity.dart';
import '../../features/admin/domain/admin_models.dart';
import '../../features/devotionals/domain/devotional.dart';
import '../../features/profile/domain/user_profile.dart';
import '../../features/social/domain/social.dart';
import '../utils/app_exception.dart';
import 'seed_data.dart';

/// Lets the dev menu force the states that are otherwise hard to reach with
/// happy-path fixtures. Every list screen has to handle all three, so make all
/// three reachable.
enum MockScenario {
  normal('Normal'),
  empty('Empty'),
  failing('Failing');

  const MockScenario(this.label);
  final String label;
}

/// The fake backend.
///
/// One in-memory store standing in for Supabase: the feature repositories are
/// thin queries over these lists, exactly as they will be thin queries over
/// Postgres in Phase 2. Keeping it in one place is what makes cross-feature
/// mutations coherent — saving an activity really does show up in the feed, in
/// history, and in the admin activity count, because they are all reading the
/// same rows.
///
/// PHASE 2: this class is replaced by a `SupabaseClient`; the repository
/// implementations beside it change their bodies and nothing above them moves.
class MockBackend {
  MockBackend({this.latency = const Duration(milliseconds: 260)}) {
    final seed = MockSeed.build();
    users.addAll(seed.users);
    activities.addAll(seed.activities);
    devotionals.addAll(seed.devotionals);
    comments.addAll(seed.comments);
    encouragements.addAll(seed.encouragements);
    follows.addAll(seed.follows);
    reports.addAll(seed.reports);
    announcements.addAll(seed.announcements);
  }

  /// Artificial round-trip time, so loading states are real rather than
  /// theoretical. Tests set this to zero.
  final Duration latency;

  final List<UserProfile> users = [];
  final List<Activity> activities = [];
  final List<Devotional> devotionals = [];
  final List<Comment> comments = [];
  final List<Encouragement> encouragements = [];
  final List<Follow> follows = [];
  final List<ModerationReport> reports = [];
  final List<Announcement> announcements = [];

  /// DEV ONLY — driven by the debug menu.
  MockScenario scenario = MockScenario.normal;

  int _sequence = 0;
  String nextId(String prefix) => '${prefix}_gen${++_sequence}';

  // ------------------------------------------------------------ transport ---

  /// A read that honours the scenario switch.
  Future<T> read<T>(T Function() query) async {
    await Future<void>.delayed(latency);
    if (scenario == MockScenario.failing) throw AppException.network;
    return query();
  }

  /// A list read. Returns nothing under [MockScenario.empty] so empty states
  /// can be exercised without deleting fixtures.
  Future<List<T>> readList<T>(List<T> Function() query) async {
    await Future<void>.delayed(latency);
    switch (scenario) {
      case MockScenario.failing:
        throw AppException.network;
      case MockScenario.empty:
        return <T>[];
      case MockScenario.normal:
        return query();
    }
  }

  /// A write. Mutations are allowed to succeed even in the empty scenario —
  /// only reads are being staged.
  Future<T> write<T>(T Function() mutation) async {
    await Future<void>.delayed(latency + const Duration(milliseconds: 120));
    if (scenario == MockScenario.failing) {
      throw const AppException(
        "That didn't save. Check your connection, then try again.",
      );
    }
    return mutation();
  }

  // --------------------------------------------------------------- lookups ---

  UserProfile userById(String id) => users.firstWhere(
    (u) => u.id == id,
    orElse: () => throw AppException.notFound,
  );

  Activity rawActivityById(String id) => activities.firstWhere(
    (a) => a.id == id,
    orElse: () => throw AppException.notFound,
  );

  Devotional devotionalById(String id) => devotionals.firstWhere(
    (d) => d.id == id,
    orElse: () => throw AppException.notFound,
  );

  void replaceUser(UserProfile updated) {
    final i = users.indexWhere((u) => u.id == updated.id);
    if (i == -1) throw AppException.notFound;
    users[i] = updated;
  }

  void replaceActivity(Activity updated) {
    final i = activities.indexWhere((a) => a.id == updated.id);
    if (i == -1) throw AppException.notFound;
    activities[i] = updated;
  }

  void replaceDevotional(Devotional updated) {
    final i = devotionals.indexWhere((d) => d.id == updated.id);
    if (i == -1) throw AppException.notFound;
    devotionals[i] = updated;
  }

  /// Fills in the social counts an [Activity] carries for a given viewer.
  /// Counts live in the join tables, not on the row, so a new encouragement is
  /// reflected everywhere at once.
  Activity hydrate(Activity activity, String viewerId) {
    return activity.copyWith(
      encouragementCount: encouragements
          .where((e) => e.activityId == activity.id)
          .length,
      commentCount: comments.where((c) => c.activityId == activity.id).length,
      encouragedByViewer: encouragements.any(
        (e) => e.activityId == activity.id && e.fromUserId == viewerId,
      ),
    );
  }

  List<Activity> hydrateAll(Iterable<Activity> source, String viewerId) =>
      source.map((a) => hydrate(a, viewerId)).toList(growable: false);
}

/// The single store every repository reads from.
final mockBackendProvider = Provider<MockBackend>((ref) => MockBackend());

/// DEV ONLY — which failure/emptiness the mock backend is simulating.
/// Replaced in Phase 2 by whatever Supabase actually returns.
class MockScenarioController extends Notifier<MockScenario> {
  @override
  MockScenario build() => MockScenario.normal;

  void set(MockScenario scenario) {
    ref.read(mockBackendProvider).scenario = scenario;
    state = scenario;
  }
}

final mockScenarioControllerProvider =
    NotifierProvider<MockScenarioController, MockScenario>(
      MockScenarioController.new,
    );
