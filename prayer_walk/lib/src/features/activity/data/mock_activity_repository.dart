import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/mock_backend/mock_backend.dart';
import '../../../core/mock_backend/route_shapes.dart';
import '../../../core/mock_backend/seed_data.dart';
import '../../auth/data/auth_providers.dart';
import '../../profile/domain/user_profile.dart';
import '../domain/activity.dart';
import '../domain/activity_repository.dart';

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
    // MOCK — a fixed fix, no device GPS this phase. Phase 3 swaps this for a
    // real position and everything above the interface is unchanged.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    return MockSeed.mockCurrentLocation;
  }

  @override
  Future<List<PrayerIntention>> suggestedIntentions() =>
      _backend.read(() => MockSeed.suggestedIntentions(DateTime.now()));

  @override
  Future<ActivityDraft> beginMockRecording({
    required ActivityType type,
    required List<PrayerIntention> intentions,
  }) async {
    // MOCK — real tracking in Phase 3. The "recording" is a pre-traced loop
    // with stats derived from it, so the live screen and summary agree.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final route = MockSeed.mockRecordingRoute();
    final distance = RouteShapes.lengthMeters(route);
    final startedAt = DateTime.now();
    final secondsPerKm = switch (type) {
      ActivityType.walk => 700,
      ActivityType.run => 335,
      ActivityType.hike => 900,
      ActivityType.cycle => 190,
    };
    final duration = Duration(
      seconds: (distance / 1000 * secondsPerKm).round(),
    );
    final points = RouteShapes.along(route, 2);
    return ActivityDraft(
      type: type,
      title: _defaultTitle(type, startedAt),
      startedAt: startedAt,
      duration: duration,
      distanceMeters: distance,
      elevationGainMeters: type == ActivityType.hike ? 186 : 24,
      route: route,
      waypoints: [
        Waypoint(
          id: _backend.nextId('w'),
          point: points[0],
          kind: WaypointKind.intercession,
          label: 'Paused here',
          elapsed: duration * 0.34,
        ),
        Waypoint(
          id: _backend.nextId('w'),
          point: points[1],
          kind: WaypointKind.stillness,
          label: 'Kept silence',
          elapsed: duration * 0.72,
        ),
      ],
      intentions: intentions,
    );
  }

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

final activityRepositoryProvider = Provider<ActivityRepository>((ref) {
  return MockActivityRepository(
    ref.watch(mockBackendProvider),
    ref.watch(currentUserIdProvider) ?? '',
  );
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
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Future.value(const []);
  return ref
      .watch(activityRepositoryProvider)
      .activitiesForUser(userId, type: ref.watch(historyFilterProvider));
});

/// Another person's activities, unfiltered — used on their profile.
final activitiesForUserProvider =
    FutureProvider.family<List<Activity>, String>(
      (ref, userId) =>
          ref.watch(activityRepositoryProvider).activitiesForUser(userId),
    );

final activityProvider = FutureProvider.family<Activity, String>(
  (ref, id) => ref.watch(activityRepositoryProvider).activityById(id),
);

final suggestedIntentionsProvider = FutureProvider<List<PrayerIntention>>(
  (ref) => ref.watch(activityRepositoryProvider).suggestedIntentions(),
);

final currentLocationProvider = FutureProvider<LatLng>(
  (ref) => ref.watch(activityRepositoryProvider).currentLocation(),
);
