/// The zone-trimming rule, in Dart, **for the owner's preview only**.
///
/// The trimming that matters happens in Postgres, in
/// `activity_trace_for_viewer`, before a single coordinate is serialised. That
/// is the whole point of the feature: a client that received the real points
/// and merely declined to draw them would already have been handed the address,
/// and anyone with the app's publishable key could read them straight off the
/// wire.
///
/// So this file is deliberately not part of the boundary, and nothing in the
/// app uses it to hide anything from anybody. It exists for one job: showing a
/// member their own walk as others will receive it, so they can check that a
/// zone covers what they meant it to before they share anything. The owner is
/// the one person entitled to both versions, and the only person this code ever
/// runs for.
///
/// It mirrors the SQL exactly — same haversine, same both-ends rule, same
/// wholesale drop of waypoints — because a preview that disagrees with the
/// server would be worse than no preview at all. If one changes, the other has
/// to. `test/zone_trimming_test.dart` is the copy of the rule that fails when
/// they drift.
library;

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'privacy_zone.dart';

/// The result of trimming: what a viewer would receive, and whether anything
/// was taken away.
class TrimmedTrace {
  const TrimmedTrace({
    required this.route,
    required this.trimmed,
    required this.removedFromStart,
    required this.removedFromEnd,
  });

  final List<LatLng> route;

  /// Whether the viewer's copy is shorter than the recorded one.
  final bool trimmed;

  final int removedFromStart;
  final int removedFromEnd;
}

/// Metres between two points on a sphere.
///
/// Haversine, mean earth radius. A zone is a few hundred metres across, over
/// which the sphere is accurate to well under a metre — the ellipsoid would be
/// a more precise answer to a question nobody is asking.
double metresBetween(LatLng a, LatLng b) {
  const earthRadius = 6371000.0;
  double radians(double degrees) => degrees * math.pi / 180;

  final dLat = radians(b.latitude - a.latitude);
  final dLng = radians(b.longitude - a.longitude);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(radians(a.latitude)) *
          math.cos(radians(b.latitude)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * earthRadius * math.asin(math.min(1, math.sqrt(h)));
}

bool _inAnyZone(LatLng point, List<PrivacyZone> zones) {
  for (final zone in zones) {
    if (metresBetween(zone.centre, point) <= zone.radiusMeters) return true;
  }
  return false;
}

/// Drops points from each end of [route] while they fall inside a zone.
///
/// **Both ends inward, and the middle left whole.** A walk that passes a zone
/// halfway through keeps those points, which looks at first like the rule
/// giving up — and is in fact the safer of the two options. Cutting a hole in
/// the middle of a trace makes the map draw a straight line across the gap
/// whose two ends sit on the circle's edge; a chord locates a centre far more
/// precisely than the honest curve running past it does.
///
/// An entirely-inside-a-zone walk returns an empty route, which the map renders
/// as no line at all.
TrimmedTrace trimRoute(List<LatLng> route, List<PrivacyZone> zones) {
  if (route.isEmpty || zones.isEmpty) {
    return TrimmedTrace(
      route: route,
      trimmed: false,
      removedFromStart: 0,
      removedFromEnd: 0,
    );
  }

  var lo = 0;
  var hi = route.length - 1;
  while (lo <= hi && _inAnyZone(route[lo], zones)) {
    lo++;
  }
  while (hi >= lo && _inAnyZone(route[hi], zones)) {
    hi--;
  }

  final kept = lo > hi
      ? const <LatLng>[]
      : route.sublist(lo, hi + 1);

  return TrimmedTrace(
    route: kept,
    trimmed: kept.length != route.length,
    removedFromStart: lo,
    removedFromEnd: route.length - 1 - hi,
  );
}

/// Which of [points] survive for a viewer. Used for waypoints, which are
/// filtered wholesale rather than from the ends: a waypoint is a point and not
/// a segment, so dropping one out of the middle leaves no line behind to give
/// it away.
List<T> withoutPointsInZones<T>(
  List<T> items,
  List<PrivacyZone> zones,
  LatLng Function(T) locate,
) {
  if (zones.isEmpty) return items;
  return [
    for (final item in items)
      if (!_inAnyZone(locate(item), zones)) item,
  ];
}
