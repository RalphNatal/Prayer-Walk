import '../../../core/widgets/trail_painter.dart';
import '../domain/activity.dart';

/// Maps domain waypoints onto what the trail renderers draw.
///
/// The adapter lives here, in the feature, rather than in the shared kit —
/// core widgets stay ignorant of the activity domain, which is what lets the
/// map and painter be reused by anything.
extension WaypointTrailX on Waypoint {
  TrailWaypoint toTrailWaypoint() =>
      TrailWaypoint(point: point, label: '${kind.label} — $label');
}

extension WaypointListTrailX on List<Waypoint> {
  List<TrailWaypoint> toTrailWaypoints() =>
      map((w) => w.toTrailWaypoint()).toList(growable: false);
}
