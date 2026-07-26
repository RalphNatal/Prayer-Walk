import 'package:latlong2/latlong.dart';

import 'activity.dart';

abstract interface class ActivityRepository {
  /// A person's activities, newest first, optionally narrowed to one type.
  Future<List<Activity>> activitiesForUser(String userId, {ActivityType? type});

  Future<Activity> activityById(String id);

  /// Where the record screen centres its map.
  ///
  /// MOCK: a fixed coordinate. Phase 3 replaces this with a real fix from the
  /// device — which is exactly why it sits behind the repository.
  Future<LatLng> currentLocation();

  /// Prompts offered when adding intentions, so the sheet never starts blank.
  Future<List<PrayerIntention>> suggestedIntentions();

  /// Produce the recording the live screen and summary will display.
  ///
  /// MOCK: returns a pre-traced route with plausible stats. Phase 3 replaces
  /// this with an actual location stream.
  Future<ActivityDraft> beginMockRecording({
    required ActivityType type,
    required List<PrayerIntention> intentions,
  });

  /// Commit a finished draft. Returns the stored activity.
  Future<Activity> saveDraft(String userId, ActivityDraft draft);

  Future<void> deleteActivity(String id);
}
