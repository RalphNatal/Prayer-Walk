import 'activity.dart';
import 'location_fix.dart';

abstract interface class ActivityRepository {
  /// A person's activities, newest first, optionally narrowed to one type.
  Future<List<Activity>> activitiesForUser(String userId, {ActivityType? type});

  Future<Activity> activityById(String id);

  /// Where the record screen centres its map — a real device fix, carrying its
  /// own accuracy and timestamp so the screen can decide how much to claim for
  /// it rather than drawing every position at full confidence, plus the access
  /// level that produced it.
  Future<LocationReading> currentLocation();

  /// Prompts offered when adding intentions, so the sheet never starts blank.
  Future<List<PrayerIntention>> suggestedIntentions();

  /// Commit a finished draft. Returns the stored activity.
  Future<Activity> saveDraft(String userId, ActivityDraft draft);

  Future<void> deleteActivity(String id);
}
