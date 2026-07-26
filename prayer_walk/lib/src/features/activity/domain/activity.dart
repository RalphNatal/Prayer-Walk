import 'package:latlong2/latlong.dart';

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
  final int encouragementCount;
  final int commentCount;
  final bool encouragedByViewer;

  Activity copyWith({
    String? title,
    String? note,
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
    );
  }

  ActivityDraft copyWith({
    String? title,
    String? note,
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
    );
  }
}
