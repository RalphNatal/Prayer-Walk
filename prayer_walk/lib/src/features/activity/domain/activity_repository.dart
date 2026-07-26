import 'package:latlong2/latlong.dart';

import 'activity.dart';

abstract interface class ActivityRepository {
  /// A person's activities, newest first, optionally narrowed to one type.
  Future<List<Activity>> activitiesForUser(String userId, {ActivityType? type});

  Future<Activity> activityById(String id);

  /// Where the record screen centres its map — a real device fix.
  Future<LatLng> currentLocation();

  /// Prompts offered when adding intentions, so the sheet never starts blank.
  Future<List<PrayerIntention>> suggestedIntentions();

  /// Commit a finished draft. Returns the stored activity.
  Future<Activity> saveDraft(String userId, ActivityDraft draft);

  Future<void> deleteActivity(String id);
}
