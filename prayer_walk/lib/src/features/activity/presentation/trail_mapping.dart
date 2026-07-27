import '../../../core/theme/app_trail_theme.dart';
import '../../../core/widgets/trail_painter.dart';
import '../domain/activity.dart';

/// Maps domain waypoints onto what the trail renderers draw.
///
/// The adapter lives here, in the feature, rather than in the shared kit —
/// core widgets stay ignorant of the activity domain, which is what lets the
/// map and painter be reused by anything.
///
/// The trail theme is a parameter for the same reason: the renderers take a
/// plain colour, and deciding which colour a *scripture* stop gets is a
/// feature-level judgement, not something the painter should know about.
extension WaypointTrailX on Waypoint {
  TrailWaypoint toTrailWaypoint(AppTrailTheme trail) => TrailWaypoint(
    point: point,
    label: '${kind.label} — $label',
    // Verses that arrived by themselves read cooler than the stops the walker
    // chose to mark, without leaving the palette.
    tint: kind == WaypointKind.scripture
        ? trail.waypointScripture
        : trail.waypointCore,
  );
}

extension WaypointListTrailX on List<Waypoint> {
  List<TrailWaypoint> toTrailWaypoints(AppTrailTheme trail) =>
      map((w) => w.toTrailWaypoint(trail)).toList(growable: false);
}
