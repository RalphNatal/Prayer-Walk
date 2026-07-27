import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/activity/domain/activity.dart';
import '../../features/admin/domain/admin_models.dart';
import '../../features/devotionals/domain/devotional.dart';
import '../../features/profile/domain/user_profile.dart';
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

/// The fake backend, for what is left on mock data.
///
/// One in-memory store standing in for Supabase. Most of it has been replaced:
/// auth, profiles, activities, the follow graph, encouragements, comments, the
/// feed and lifetime stats are all real Postgres now, and the lists that backed
/// them are gone with the repositories that read them.
///
/// What remains here is what remains mocked — devotionals and the admin console
/// (members and activities read for its metrics, plus moderation reports and
/// announcements). It goes away entirely with the last de-mock.
class MockBackend {
  MockBackend({this.latency = const Duration(milliseconds: 260)}) {
    final seed = MockSeed.build();
    users.addAll(seed.users);
    activities.addAll(seed.activities);
    devotionals.addAll(seed.devotionals);
    reports.addAll(seed.reports);
    announcements.addAll(seed.announcements);
  }

  /// Artificial round-trip time, so loading states are real rather than
  /// theoretical. Tests set this to zero.
  final Duration latency;

  final List<UserProfile> users = [];
  final List<Activity> activities = [];
  final List<Devotional> devotionals = [];
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
