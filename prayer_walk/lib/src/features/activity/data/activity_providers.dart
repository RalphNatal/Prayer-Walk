import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_providers.dart';
import '../domain/activity.dart';
import '../domain/activity_repository.dart';
import 'location_service.dart';
import 'supabase_activity_repository.dart';

/// Real recorded activities, in Supabase.
///
/// Rebuilt when the session changes, because the rows it returns are hydrated
/// for whoever is signed in — the encouragement state on a card belongs to the
/// viewer, not to the walk.
final activityRepositoryProvider = Provider<ActivityRepository>((ref) {
  return SupabaseActivityRepository(
    ref.watch(locationServiceProvider),
    ref.watch(currentAuthUserIdProvider),
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
  final userId = ref.watch(currentAuthUserIdProvider);
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

/// What the device can currently tell us, for the record screen.
///
/// Resolves to a reading with a null fix — rather than to some stand-in
/// position — whenever there is nothing trustworthy to show, so the screen can
/// render its locating state and name the actual reason.
final currentLocationProvider = FutureProvider<LocationReading>(
  (ref) => ref.watch(activityRepositoryProvider).currentLocation(),
);
