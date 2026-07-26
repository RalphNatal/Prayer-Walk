import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/mock_backend/mock_backend.dart';
import '../../../core/mock_backend/seed_data.dart';
import '../../auth/data/auth_providers.dart';
import '../../profile/domain/user_profile.dart';
import '../domain/activity.dart';
import '../domain/activity_repository.dart';
import 'location_service.dart';
import 'supabase_activity_repository.dart';

class MockActivityRepository implements ActivityRepository {
  MockActivityRepository(this._backend, this._viewerId);

  final MockBackend _backend;

  /// Whose encouragement state the returned rows are hydrated for.
  final String _viewerId;

  @override
  Future<List<Activity>> activitiesForUser(String userId, {ActivityType? type}) {
    return _backend.readList(() {
      final rows =
          _backend.activities
              .where((a) => a.userId == userId)
              .where((a) => type == null || a.type == type)
              .toList()
            ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
      return _backend.hydrateAll(rows, _viewerId);
    });
  }

  @override
  Future<Activity> activityById(String id) => _backend.read(
    () => _backend.hydrate(_backend.rawActivityById(id), _viewerId),
  );

  @override
  Future<LatLng> currentLocation() async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    return MockSeed.mockCurrentLocation;
  }

  @override
  Future<List<PrayerIntention>> suggestedIntentions() =>
      _backend.read(() => MockSeed.suggestedIntentions(DateTime.now()));

  @override
  Future<Activity> saveDraft(String userId, ActivityDraft draft) {
    return _backend.write(() {
      final activity = Activity(
        id: _backend.nextId('a'),
        userId: userId,
        type: draft.type,
        title: draft.title.trim().isEmpty
            ? _defaultTitle(draft.type, draft.startedAt)
            : draft.title.trim(),
        startedAt: draft.startedAt,
        duration: draft.duration,
        distanceMeters: draft.distanceMeters,
        elevationGainMeters: draft.elevationGainMeters,
        route: draft.route,
        waypoints: draft.waypoints,
        intentions: draft.intentions,
        note: draft.note.trim(),
      );
      _backend.activities.add(activity);

      final walker = _backend.userById(userId);
      final stats = walker.stats;
      _backend.replaceUser(
        walker.copyWith(
          stats: LifetimeStats(
            totalDistanceMeters: stats.totalDistanceMeters + activity.distanceMeters,
            totalDuration: stats.totalDuration + activity.duration,
            activityCount: stats.activityCount + 1,
            streakDays: stats.streakDays,
            intentionCount: stats.intentionCount + activity.intentions.length,
          ),
        ),
      );
      return activity;
    });
  }

  @override
  Future<void> deleteActivity(String id) {
    return _backend.write(() {
      _backend.activities.removeWhere((a) => a.id == id);
      _backend.comments.removeWhere((c) => c.activityId == id);
      _backend.encouragements.removeWhere((e) => e.activityId == id);
    });
  }

  String _defaultTitle(ActivityType type, DateTime at) {
    final hour = at.hour;
    final partOfDay = hour < 11
        ? 'Morning'
        : hour < 15
        ? 'Midday'
        : hour < 19
        ? 'Afternoon'
        : 'Evening';
    return '$partOfDay ${type.label.toLowerCase()}';
  }
}

/// Real recorded activities, in Supabase.
final activityRepositoryProvider = Provider<ActivityRepository>((ref) {
  return SupabaseActivityRepository(ref.watch(locationServiceProvider));
});

/// Filter for the History screen.
final historyFilterProvider = NotifierProvider<HistoryFilter, ActivityType?>(
  HistoryFilter.new,
);

class HistoryFilter extends Notifier<ActivityType?> {
  @override
  ActivityType? build() => null;

  void set(ActivityType? type) => state = type;
}

/// The signed-in person's activities, honouring the history filter.
final historyProvider = FutureProvider<List<Activity>>((ref) {
  final userId = ref.watch(currentAuthUserIdProvider);
  if (userId == null) return Future.value(const []);
  return ref
      .watch(activityRepositoryProvider)
      .activitiesForUser(userId, type: ref.watch(historyFilterProvider));
});

/// The seeded dataset, still serving the feed and the seeded members.
final mockActivityRepositoryProvider = Provider<ActivityRepository>((ref) {
  return MockActivityRepository(
    ref.watch(mockBackendProvider),
    ref.watch(currentUserIdProvider) ?? '',
  );
});

/// Real rows are uuids; every seeded id is `a_1` / `u_maria`.
///
/// PHASE BRIDGE: the feed and the social screens still hand out seeded ids, and
/// those rows exist only in the mock backend. Routing by id shape keeps both
/// alive while the two datasets overlap. Delete this — and the mock repository
/// with it — the moment feed and social move to Supabase.
bool _isRealId(String id) => RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
).hasMatch(id);

ActivityRepository _repoForId(Ref ref, String id) => _isRealId(id)
    ? ref.watch(activityRepositoryProvider)
    : ref.watch(mockActivityRepositoryProvider);

/// The repository that owns a given activity id — for writes from a screen
/// that could be looking at either dataset. Part of the same bridge.
final activityRepositoryForIdProvider =
    Provider.family<ActivityRepository, String>(
      (ref, id) => _repoForId(ref, id),
    );

/// Another person's activities, unfiltered — used on their profile.
final activitiesForUserProvider =
    FutureProvider.family<List<Activity>, String>(
      (ref, userId) => _repoForId(ref, userId).activitiesForUser(userId),
    );

final activityProvider = FutureProvider.family<Activity, String>(
  (ref, id) => _repoForId(ref, id).activityById(id),
);

final suggestedIntentionsProvider = FutureProvider<List<PrayerIntention>>(
  (ref) => ref.watch(activityRepositoryProvider).suggestedIntentions(),
);

final currentLocationProvider = FutureProvider<LatLng>(
  (ref) => ref.watch(activityRepositoryProvider).currentLocation(),
);
