import 'mock_backend/mock_backend.dart';
import 'mock_backend/seed_data.dart';
import 'package:prayer_walk/src/features/activity/data/location_service.dart';
import 'package:prayer_walk/src/features/activity/domain/activity.dart';
import 'package:prayer_walk/src/features/activity/domain/activity_repository.dart';
import 'package:prayer_walk/src/features/profile/domain/user_profile.dart';

/// An [ActivityRepository] over the seeded dataset, for widget tests.
///
/// This used to ship in `lib/` while the app's content was mock. It lives here
/// now because that is all it was ever for: a widget test has no Supabase, and
/// the repository interface is the seam to swap at — the same seam the app
/// swaps at in `main`.
class SeededActivityRepository implements ActivityRepository {
  SeededActivityRepository(this._backend);

  final MockBackend _backend;

  @override
  Future<List<Activity>> activitiesForUser(String userId, {ActivityType? type}) {
    return _backend.readList(() {
      final rows =
          _backend.activities
              .where((a) => a.userId == userId)
              .where((a) => type == null || a.type == type)
              .toList()
            ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
      return rows;
    });
  }

  @override
  Future<Activity> activityById(String id) =>
      _backend.read(() => _backend.rawActivityById(id));

  /// There is no such thing as a seeded device position.
  @override
  Future<LocationReading> currentLocation() async => throw UnsupportedError(
    'The seeded dataset has no device position.',
  );

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
            totalDistanceMeters:
                stats.totalDistanceMeters + activity.distanceMeters,
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
    return _backend.write(() => _backend.activities.removeWhere((a) => a.id == id));
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
