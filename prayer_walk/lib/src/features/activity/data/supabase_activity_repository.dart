import 'package:flutter/foundation.dart' show kDebugMode;

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/utils/app_logger.dart';
import '../domain/activity.dart';
import '../domain/activity_repository.dart';
import 'activity_row_mapper.dart';
import 'location_service.dart';

/// Real recorded activities, read and written through RLS.
///
/// Reads go through the `activity_detail` / `activities_for` functions rather
/// than a plain select, because a card is never just the activity: it carries
/// the encouragement and comment counts and whether *this* viewer has already
/// encouraged it. Those come back on the same row, so a list of walks is one
/// round trip however long the list is.
///
/// [_viewerId] is whose encouragement state the returned rows are hydrated for
/// — the signed-in person, or null while signed out. The row shape is the same
/// either way; `encouragedByViewer` is simply always false for nobody.
class SupabaseActivityRepository implements ActivityRepository {
  const SupabaseActivityRepository(this._location, this._viewerId);

  final LocationService _location;
  final String? _viewerId;

  static const _tag = 'PW-ACT';

  @override
  Future<List<Activity>> activitiesForUser(
    String userId, {
    ActivityType? type,
  }) async {
    final rows =
        await supabase.rpc(
              'activities_for',
              params: {
                'target': userId,
                'viewer': _viewerId,
                'type_filter': type?.name,
              },
            )
            as List<dynamic>;

    return [
      for (final row in rows) activityFromRow(row as Map<String, dynamic>),
    ];
  }

  @override
  Future<Activity> activityById(String id) async {
    final rows =
        await supabase.rpc(
              'activity_detail',
              params: {'activity_id': id, 'viewer': _viewerId},
            )
            as List<dynamic>;

    // No row means deleted, or hidden from this viewer by RLS. Both read the
    // same to the person looking at a dead link.
    if (rows.isEmpty) throw AppException.notFound;
    return activityFromRow(rows.first as Map<String, dynamic>);
  }

  /// Never throws for an ordinary "no". A refusal, a switched-off radio and a
  /// GPS that hasn't locked yet are all real answers the screen renders
  /// differently — turning them into one exception would collapse them back
  /// into a single unhelpful error, which is where a fabricated centre becomes
  /// tempting again.
  @override
  Future<LocationReading> currentLocation() => _location.read();

  @override
  Future<List<PrayerIntention>> suggestedIntentions() async {
    // Still the static prompt list — de-mocking these is out of scope here and
    // there is no table behind them yet.
    return _staticSuggestions();
  }

  @override
  Future<Activity> saveDraft(String userId, ActivityDraft draft) async {
    final payload = {
      'user_id': userId,
      'type': draft.type.name,
      'title': draft.title.trim(),
      'started_at': draft.startedAt.toUtc().toIso8601String(),
      'duration_seconds': draft.duration.inSeconds,
      'distance_meters': draft.distanceMeters,
      'elevation_gain_meters': draft.elevationGainMeters,
      'route': encodeRoute(draft.route),
      'waypoints': encodeWaypoints(draft.waypoints),
      'intentions': encodeIntentions(draft.intentions),
      'note': draft.note.trim(),
      // Whatever the recorder managed to resolve while the walker was on
      // the summary screen. Null is written as null — the save is never
      // delayed to go and look it up.
      'place_name': draft.placeName,
    };

    try {
      final row = await supabase
          .from('activities')
          .insert(payload)
          .select(activityColumns)
          .single();
      // A walk nobody has seen yet has no encouragement and no comments, so the
      // plain row's zeros are the truth here rather than a placeholder.
      return activityFromRow(row);
    } catch (error) {
      // Keys, never values — a walk's route and note are the walker's, and this
      // line can end up in logcat. What it answers is the question a 42703
      // raises: which column did we send that the server does not have?
      if (kDebugMode) {
        AppLogger.debug(
          _tag,
          'insert into activities failed (${error.runtimeType}); '
          'payload keys: ${payload.keys.join(', ')}',
        );
      }
      rethrow;
    }
  }

  @override
  Future<void> deleteActivity(String id) async {
    // RLS scopes this to the owner — a delete of someone else's row simply
    // matches nothing. Comments and encouragements go with it on cascade.
    await supabase.from('activities').delete().eq('id', id);
  }

  static List<PrayerIntention> _staticSuggestions() {
    final now = DateTime.now();
    const prompts = <(String, PrayerCategory)>[
      ('For my family', PrayerCategory.family),
      ('For our parish', PrayerCategory.community),
      ('For someone who is ill', PrayerCategory.healing),
      ('In thanksgiving', PrayerCategory.gratitude),
      ('For a decision I am facing', PrayerCategory.guidance),
      ('For peace where there is war', PrayerCategory.world),
    ];
    return [
      for (var i = 0; i < prompts.length; i++)
        PrayerIntention(
          id: 'i_suggested_$i',
          text: prompts[i].$1,
          category: prompts[i].$2,
          createdAt: now,
        ),
    ];
  }
}

/// The device couldn't produce a fix. Phrased for the person.
class LocationUnavailable implements Exception {
  const LocationUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}
