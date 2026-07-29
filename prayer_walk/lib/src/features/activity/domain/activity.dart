import 'package:latlong2/latlong.dart';

import '../../privacy/domain/activity_visibility.dart';

/// The four ways a walk gets recorded.
enum ActivityType {
  walk('Walk', 'Walking'),
  run('Run', 'Running'),
  hike('Hike', 'Hiking'),
  cycle('Ride', 'Riding');

  const ActivityType(this.label, this.gerund);

  /// Noun, as it appears on chips and filters: "Walk".
  final String label;

  /// Verb form, for sentences: "Maria was walking".
  final String gerund;

  /// Rides read better in km/h; everything else in min/km.
  bool get usesSpeed => this == ActivityType.cycle;
}

/// What a prayer waypoint marks. Drives the candle icon's tint on the trail.
enum WaypointKind {
  intercession('Interceded'),
  gratitude('Gave thanks'),
  scripture('Read scripture'),
  stillness('Kept silence');

  const WaypointKind(this.label);
  final String label;
}

/// A point on the route the walker tagged while praying.
class Waypoint {
  const Waypoint({
    required this.id,
    required this.point,
    required this.kind,
    required this.label,
    this.note = '',
    this.elapsed = Duration.zero,
  });

  final String id;
  final LatLng point;
  final WaypointKind kind;
  final String label;
  final String note;

  /// How far into the activity it was dropped.
  final Duration elapsed;
}

enum PrayerCategory {
  family('Family'),
  community('Community'),
  healing('Healing'),
  gratitude('Gratitude'),
  guidance('Guidance'),
  world('World');

  const PrayerCategory(this.label);
  final String label;
}

/// Something the walker carries with them for the whole activity.
class PrayerIntention {
  const PrayerIntention({
    required this.id,
    required this.text,
    required this.category,
    required this.createdAt,
  });

  final String id;
  final String text;
  final PrayerCategory category;
  final DateTime createdAt;
}

class Activity {
  const Activity({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.startedAt,
    required this.duration,
    required this.distanceMeters,
    required this.elevationGainMeters,
    required this.route,
    this.waypoints = const [],
    this.intentions = const [],
    this.note = '',
    this.placeName,
    this.visibility = ActivityVisibility.standard,
    this.routeTrimmed = false,
    this.encouragementCount = 0,
    this.commentCount = 0,
    this.encouragedByViewer = false,
  });

  final String id;
  final String userId;
  final ActivityType type;
  final String title;
  final DateTime startedAt;
  final Duration duration;
  final double distanceMeters;
  final double elevationGainMeters;

  /// The traced route. Empty is valid — an activity can be logged without one.
  final List<LatLng> route;
  final List<Waypoint> waypoints;
  final List<PrayerIntention> intentions;
  final String note;

  /// Where the walk happened, in words — "Antipolo", "Kreuzberg". Resolved once
  /// by reverse geocoding when the walk is saved and stored on the row, so
  /// reading a walk never costs a geocoding request. Null for walks recorded
  /// before this existed, for walks with no route, and whenever the lookup
  /// failed — it is a nicety, and nothing waits on it.
  final String? placeName;

  /// Who this walk is for. Set on the summary screen when it is saved, and
  /// changeable afterwards from the walk itself. The value on this object is a
  /// copy of what the row says; the SELECT policy on `activities` is what
  /// actually decides who reads it.
  final ActivityVisibility visibility;

  /// Whether the route on this object is shorter than the one that was
  /// recorded, because the server dropped points falling inside one of the
  /// walker's privacy zones before sending it.
  ///
  /// Always false for the owner, who receives their whole trace. For everyone
  /// else it is what lets the map say so out loud — [distanceMeters] is still
  /// the full recorded walk, deliberately, so the number and the line disagree
  /// and the card has to explain why rather than quietly showing a distance
  /// that contradicts what is drawn.
  final bool routeTrimmed;

  final int encouragementCount;
  final int commentCount;
  final bool encouragedByViewer;

  Activity copyWith({
    String? title,
    String? note,
    String? placeName,
    ActivityVisibility? visibility,
    List<PrayerIntention>? intentions,
    List<Waypoint>? waypoints,
    int? encouragementCount,
    int? commentCount,
    bool? encouragedByViewer,
  }) {
    return Activity(
      id: id,
      userId: userId,
      type: type,
      title: title ?? this.title,
      startedAt: startedAt,
      duration: duration,
      distanceMeters: distanceMeters,
      elevationGainMeters: elevationGainMeters,
      route: route,
      waypoints: waypoints ?? this.waypoints,
      intentions: intentions ?? this.intentions,
      note: note ?? this.note,
      placeName: placeName ?? this.placeName,
      visibility: visibility ?? this.visibility,
      routeTrimmed: routeTrimmed,
      encouragementCount: encouragementCount ?? this.encouragementCount,
      commentCount: commentCount ?? this.commentCount,
      encouragedByViewer: encouragedByViewer ?? this.encouragedByViewer,
    );
  }
}

/// A finished-but-unsaved activity, handed from the record flow to the summary
/// screen. Phase 3 fills this from the real location stream; today the
/// repository hands back a pre-traced walk.
class ActivityDraft {
  const ActivityDraft({
    required this.type,
    required this.title,
    required this.startedAt,
    required this.duration,
    required this.distanceMeters,
    required this.elevationGainMeters,
    required this.route,
    required this.waypoints,
    required this.intentions,
    this.note = '',
    this.placeName,
    this.visibility = ActivityVisibility.standard,
  });

  final ActivityType type;
  final String title;
  final DateTime startedAt;
  final Duration duration;
  final double distanceMeters;
  final double elevationGainMeters;
  final List<LatLng> route;
  final List<Waypoint> waypoints;
  final List<PrayerIntention> intentions;
  final String note;

  /// Filled in asynchronously after the walk finishes, if the lookup lands
  /// before the walker saves. Null is entirely ordinary — see
  /// [Activity.placeName].
  final String? placeName;

  /// Who the finished walk will be for. Seeded from the member's standing
  /// default and changeable on the summary screen, which is the last moment
  /// before a route leaves the phone and therefore the right one to ask.
  final ActivityVisibility visibility;

  /// The partial state shown on the live screen: the first [fraction] of the
  /// traced route with stats scaled to match, so the mock reads as a walk in
  /// progress rather than a finished one.
  ActivityDraft sliced(double fraction) {
    final cut = (route.length * fraction).round().clamp(2, route.length);
    return ActivityDraft(
      type: type,
      title: title,
      startedAt: startedAt,
      duration: duration * fraction,
      distanceMeters: distanceMeters * fraction,
      elevationGainMeters: elevationGainMeters * fraction,
      route: route.sublist(0, cut),
      waypoints: waypoints
          .where((w) => w.elapsed <= duration * fraction)
          .toList(growable: false),
      intentions: intentions,
      note: note,
      placeName: placeName,
      visibility: visibility,
    );
  }

  ActivityDraft copyWith({
    String? title,
    String? note,
    String? placeName,
    ActivityVisibility? visibility,
    List<PrayerIntention>? intentions,
    List<Waypoint>? waypoints,
  }) {
    return ActivityDraft(
      type: type,
      title: title ?? this.title,
      startedAt: startedAt,
      duration: duration,
      distanceMeters: distanceMeters,
      elevationGainMeters: elevationGainMeters,
      route: route,
      waypoints: waypoints ?? this.waypoints,
      intentions: intentions ?? this.intentions,
      note: note ?? this.note,
      placeName: placeName ?? this.placeName,
      visibility: visibility ?? this.visibility,
    );
  }
}
