import 'package:latlong2/latlong.dart';

import '../../../core/supabase/supabase_client.dart';
import '../domain/activity.dart';
import '../domain/activity_repository.dart';
import 'location_service.dart';

/// Real recorded activities, read and written through RLS.
///
/// Route, waypoints and intentions live as JSONB on the row — see the
/// `20260726010000_activities.sql` migration for why. All the encoding and
/// decoding of that shape is in this file; nothing above the interface knows
/// the route is stored as `[[lat,lng], ...]`.
///
/// Social counts are hard zeros for now: there are no encouragement or comment
/// tables yet, and inventing numbers under a real walk would be a lie. They
/// become real in the social phase.
class SupabaseActivityRepository implements ActivityRepository {
  const SupabaseActivityRepository(this._location);

  final LocationService _location;

  static const _columns =
      'id, user_id, type, title, started_at, duration_seconds, distance_meters, '
      'elevation_gain_meters, route, waypoints, intentions, note, place_name, '
      'created_at';

  @override
  Future<List<Activity>> activitiesForUser(
    String userId, {
    ActivityType? type,
  }) async {
    final filter = supabase
        .from('activities')
        .select(_columns)
        .eq('user_id', userId);

    final rows = await (type == null ? filter : filter.eq('type', type.name))
        .order('started_at', ascending: false);

    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<Activity> activityById(String id) async {
    final row = await supabase
        .from('activities')
        .select(_columns)
        .eq('id', id)
        .single();
    return _fromRow(row);
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
    final row = await supabase
        .from('activities')
        .insert({
          'user_id': userId,
          'type': draft.type.name,
          'title': draft.title.trim(),
          'started_at': draft.startedAt.toUtc().toIso8601String(),
          'duration_seconds': draft.duration.inSeconds,
          'distance_meters': draft.distanceMeters,
          'elevation_gain_meters': draft.elevationGainMeters,
          'route': _encodeRoute(draft.route),
          'waypoints': _encodeWaypoints(draft.waypoints),
          'intentions': _encodeIntentions(draft.intentions),
          'note': draft.note.trim(),
          // Whatever the recorder managed to resolve while the walker was on
          // the summary screen. Null is written as null — the save is never
          // delayed to go and look it up.
          'place_name': draft.placeName,
        })
        .select(_columns)
        .single();
    return _fromRow(row);
  }

  @override
  Future<void> deleteActivity(String id) async {
    // RLS scopes this to the owner — a delete of someone else's row simply
    // matches nothing.
    await supabase.from('activities').delete().eq('id', id);
  }

  // ------------------------------------------------------------- encoding ---

  static List<List<double>> _encodeRoute(List<LatLng> route) => [
    for (final point in route) [point.latitude, point.longitude],
  ];

  static List<Map<String, dynamic>> _encodeWaypoints(List<Waypoint> waypoints) => [
    for (final waypoint in waypoints)
      {
        'lat': waypoint.point.latitude,
        'lng': waypoint.point.longitude,
        'kind': waypoint.kind.name,
        'label': waypoint.label,
        'note': waypoint.note,
        'elapsed_seconds': waypoint.elapsed.inSeconds,
      },
  ];

  static List<Map<String, dynamic>> _encodeIntentions(
    List<PrayerIntention> intentions,
  ) => [
    for (final intention in intentions)
      {'text': intention.text, 'category': intention.category.name},
  ];

  // ------------------------------------------------------------- decoding ---

  Activity _fromRow(Map<String, dynamic> row) {
    final id = row['id'] as String;
    final startedAt =
        DateTime.tryParse((row['started_at'] as String?) ?? '')?.toLocal() ??
        DateTime.now();

    return Activity(
      id: id,
      userId: row['user_id'] as String,
      type: _typeFrom(row['type'] as String?),
      title: (row['title'] as String?) ?? '',
      startedAt: startedAt,
      duration: Duration(seconds: (row['duration_seconds'] as num?)?.toInt() ?? 0),
      distanceMeters: (row['distance_meters'] as num?)?.toDouble() ?? 0,
      elevationGainMeters:
          (row['elevation_gain_meters'] as num?)?.toDouble() ?? 0,
      route: _decodeRoute(row['route']),
      waypoints: _decodeWaypoints(row['waypoints'], id),
      intentions: _decodeIntentions(row['intentions'], id, startedAt),
      note: (row['note'] as String?) ?? '',
      placeName: (row['place_name'] as String?)?.trim().isNotEmpty ?? false
          ? (row['place_name'] as String).trim()
          : null,
      // No social tables yet — see the class doc.
    );
  }

  static ActivityType _typeFrom(String? value) => ActivityType.values.firstWhere(
    (t) => t.name == value,
    orElse: () => ActivityType.walk,
  );

  static List<LatLng> _decodeRoute(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final pair in raw)
        if (pair is List && pair.length >= 2)
          LatLng((pair[0] as num).toDouble(), (pair[1] as num).toDouble()),
    ];
  }

  static List<Waypoint> _decodeWaypoints(Object? raw, String activityId) {
    if (raw is! List) return const [];
    var index = 0;
    return [
      for (final item in raw)
        if (item is Map)
          Waypoint(
            // Waypoints have no ids of their own in JSONB. A positional id is
            // enough — it is stable for a given row and only ever used as a
            // widget key.
            id: '${activityId}_w${index++}',
            point: LatLng(
              (item['lat'] as num).toDouble(),
              (item['lng'] as num).toDouble(),
            ),
            kind: WaypointKind.values.firstWhere(
              (k) => k.name == item['kind'],
              orElse: () => WaypointKind.intercession,
            ),
            label: (item['label'] as String?) ?? '',
            note: (item['note'] as String?) ?? '',
            elapsed: Duration(
              seconds: (item['elapsed_seconds'] as num?)?.toInt() ?? 0,
            ),
          ),
    ];
  }

  static List<PrayerIntention> _decodeIntentions(
    Object? raw,
    String activityId,
    DateTime startedAt,
  ) {
    if (raw is! List) return const [];
    var index = 0;
    return [
      for (final item in raw)
        if (item is Map)
          PrayerIntention(
            id: '${activityId}_i${index++}',
            text: (item['text'] as String?) ?? '',
            category: PrayerCategory.values.firstWhere(
              (c) => c.name == item['category'],
              orElse: () => PrayerCategory.community,
            ),
            // Intentions aren't timestamped in JSONB; the walk's start is the
            // closest honest answer and nothing renders this yet.
            createdAt: startedAt,
          ),
    ];
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
