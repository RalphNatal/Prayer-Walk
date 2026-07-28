import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prayer_walk/src/core/utils/app_exception.dart';
import 'package:prayer_walk/src/features/activity/domain/activity.dart';
import 'package:prayer_walk/src/features/profile/domain/user_profile.dart';

import 'seed_data.dart';

/// An in-memory store behind the repository doubles, for widget tests.
///
/// This used to be the app's fake backend, standing in for Supabase while the
/// features were built. Nothing in `lib/` reads it any more — auth, profiles,
/// activities, the follow graph, the feed, scripture, devotionals and the whole
/// admin console are real Postgres now. It survives here as a test fixture
/// because a widget test still has no backend, and `SeededActivityRepository`
/// needs somewhere for its walks to live.
///
/// The failure and emptiness scenarios went with the dev menu that drove them.
/// A test that wants a failure now states it at the repository seam, which is
/// both clearer and local to the test asking for it.
class MockBackend {
  MockBackend({this.latency = Duration.zero}) {
    final seed = MockSeed.build();
    users.addAll(seed.users);
    activities.addAll(seed.activities);
  }

  /// Artificial round-trip time. Zero by default: a widget test pumping frames
  /// has no use for a delay it then has to wait out.
  final Duration latency;

  final List<UserProfile> users = [];
  final List<Activity> activities = [];

  int _sequence = 0;
  String nextId(String prefix) => '${prefix}_gen${++_sequence}';

  // ------------------------------------------------------------ transport ---

  Future<T> read<T>(T Function() query) async {
    await Future<void>.delayed(latency);
    return query();
  }

  Future<List<T>> readList<T>(List<T> Function() query) async {
    await Future<void>.delayed(latency);
    return query();
  }

  Future<T> write<T>(T Function() mutation) async {
    await Future<void>.delayed(latency);
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
}

/// The single store the test doubles read from.
final mockBackendProvider = Provider<MockBackend>((ref) => MockBackend());
