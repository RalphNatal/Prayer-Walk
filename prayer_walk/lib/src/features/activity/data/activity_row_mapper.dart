import 'package:latlong2/latlong.dart';

import '../domain/activity.dart';

/// Row ⇄ [Activity], in one place.
///
/// Route, waypoints and intentions live as JSONB on the row — see the
/// `20260726010000_activities.sql` migration for why. All the encoding and
/// decoding of that shape is here; nothing above the repository interface knows
/// the route is stored as `[[lat,lng], ...]`.
///
/// Two row shapes come through: a plain `activities` row, and an
/// `activity_card` from `feed_for` / `activities_for` / `activity_detail`,
/// which carries the same columns plus the social counts. Both map here, so a
/// walk reads the same whichever query found it.

/// The `activities` columns a plain select needs. The SQL functions return the
/// same set — keeping the list next to the mapper is what stops them drifting.
const activityColumns =
    'id, user_id, type, title, started_at, duration_seconds, distance_meters, '
    'elevation_gain_meters, route, waypoints, intentions, note, place_name, '
    'created_at';

Activity activityFromRow(Map<String, dynamic> row) {
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
    elevationGainMeters: (row['elevation_gain_meters'] as num?)?.toDouble() ?? 0,
    route: _decodeRoute(row['route']),
    waypoints: _decodeWaypoints(row['waypoints'], id),
    intentions: _decodeIntentions(row['intentions'], id, startedAt),
    note: (row['note'] as String?) ?? '',
    placeName: (row['place_name'] as String?)?.trim().isNotEmpty ?? false
        ? (row['place_name'] as String).trim()
        : null,
    // Absent on a plain `activities` row — a walk read straight from the table
    // reports no encouragement rather than an unknown amount of it.
    encouragementCount: (row['encouragement_count'] as num?)?.toInt() ?? 0,
    commentCount: (row['comment_count'] as num?)?.toInt() ?? 0,
    encouragedByViewer: (row['encouraged_by_viewer'] as bool?) ?? false,
  );
}

// --------------------------------------------------------------- encoding ---

List<List<double>> encodeRoute(List<LatLng> route) => [
  for (final point in route) [point.latitude, point.longitude],
];

List<Map<String, dynamic>> encodeWaypoints(List<Waypoint> waypoints) => [
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

List<Map<String, dynamic>> encodeIntentions(List<PrayerIntention> intentions) => [
  for (final intention in intentions)
    {'text': intention.text, 'category': intention.category.name},
];

// --------------------------------------------------------------- decoding ---

ActivityType _typeFrom(String? value) => ActivityType.values.firstWhere(
  (t) => t.name == value,
  orElse: () => ActivityType.walk,
);

List<LatLng> _decodeRoute(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final pair in raw)
      if (pair is List && pair.length >= 2)
        LatLng((pair[0] as num).toDouble(), (pair[1] as num).toDouble()),
  ];
}

List<Waypoint> _decodeWaypoints(Object? raw, String activityId) {
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

List<PrayerIntention> _decodeIntentions(
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
