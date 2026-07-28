import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Hand-authored route generators for the seeded activities.
///
/// Each shape is a different silhouette — a loop, a lemniscate, switchbacks up
/// a ridge, a river meander — because the whole point of the gradient trail is
/// that it is *read*. Ten near-identical blobs would hide it. Every shape is
/// deterministic, so a given seed draws the same walk on every launch.
abstract final class RouteShapes {
  static const double _kmPerDegLat = 110.574;
  static const double _kmPerDegLngAtEquator = 111.320;

  /// Move [eastKm]/[northKm] from [origin] in flat-earth approximation. Over
  /// the 1–15 km these routes span, the error is far below what a map at this
  /// zoom can show.
  static LatLng offset(LatLng origin, double eastKm, double northKm) {
    final lat = origin.latitude + northKm / _kmPerDegLat;
    final lngScale =
        _kmPerDegLngAtEquator * math.cos(origin.latitude * math.pi / 180);
    return LatLng(lat, origin.longitude + eastKm / lngScale);
  }

  /// Total length of a traced route, in metres.
  static double lengthMeters(List<LatLng> route) {
    if (route.length < 2) return 0;
    const calculator = Distance();
    var total = 0.0;
    for (var i = 1; i < route.length; i++) {
      total += calculator.distance(route[i - 1], route[i]);
    }
    return total;
  }

  /// A closed neighbourhood loop with an irregular, organic edge.
  static List<LatLng> loop(
    LatLng center, {
    double radiusKm = 0.8,
    int seed = 1,
    int points = 72,
    double wobble = 0.28,
  }) {
    final rng = _Rng(seed);
    final drift = List.generate(6, (_) => rng.symmetric());
    return List.generate(points + 1, (i) {
      final t = i / points * 2 * math.pi;
      var r = radiusKm;
      for (var h = 0; h < drift.length; h++) {
        r += radiusKm * wobble * drift[h] * math.sin((h + 2) * t) / (h + 2);
      }
      return offset(center, r * math.cos(t), r * math.sin(t) * 0.82);
    });
  }

  /// Out along a wandering path, then back a street over.
  static List<LatLng> outAndBack(
    LatLng start, {
    double lengthKm = 2.4,
    double bearingDeg = 35,
    int seed = 2,
    int points = 48,
  }) {
    final rng = _Rng(seed);
    final theta = bearingDeg * math.pi / 180;
    final wobbles = List.generate(4, (_) => rng.symmetric());
    List<LatLng> leg(double lateral) => List.generate(points + 1, (i) {
      final t = i / points;
      var side = lateral;
      for (var h = 0; h < wobbles.length; h++) {
        side += 0.10 * wobbles[h] * math.sin((h + 1) * t * math.pi * 1.6);
      }
      final along = t * lengthKm;
      return offset(
        start,
        along * math.cos(theta) - side * math.sin(theta),
        along * math.sin(theta) + side * math.cos(theta),
      );
    });
    return [...leg(0), ...leg(0.09).reversed];
  }

  /// A lemniscate — two loops crossing at the chapel in the middle.
  static List<LatLng> figureEight(
    LatLng center, {
    double radiusKm = 0.9,
    int points = 96,
  }) {
    return List.generate(points + 1, (i) {
      final t = i / points * 2 * math.pi;
      final denom = 1 + math.sin(t) * math.sin(t);
      return offset(
        center,
        radiusKm * math.cos(t) / denom,
        radiusKm * math.sin(t) * math.cos(t) / denom * 1.5,
      );
    });
  }

  /// Switchbacks climbing a ridge — the hiking silhouette.
  static List<LatLng> switchbacks(
    LatLng base, {
    double riseKm = 2.2,
    double widthKm = 0.55,
    int legs = 9,
    int seed = 3,
  }) {
    final rng = _Rng(seed);
    final route = <LatLng>[];
    for (var i = 0; i <= legs; i++) {
      final north = riseKm * i / legs;
      final east = (i.isEven ? -widthKm : widthKm) / 2 * (1 - i / (legs * 2.4));
      // Bend each leg so the turns are rounded, not stapled.
      const steps = 8;
      for (var s = 0; s <= steps; s++) {
        final t = s / steps;
        final prevEast = i == 0
            ? 0.0
            : (i - 1).isEven
            ? -widthKm / 2 * (1 - (i - 1) / (legs * 2.4))
            : widthKm / 2 * (1 - (i - 1) / (legs * 2.4));
        final prevNorth = riseKm * (i == 0 ? 0 : i - 1) / legs;
        route.add(
          offset(
            base,
            prevEast + (east - prevEast) * t + 0.02 * rng.symmetric(),
            prevNorth + (north - prevNorth) * t,
          ),
        );
      }
    }
    return route;
  }

  /// Tightening circuits of a plaza.
  static List<LatLng> spiral(
    LatLng center, {
    double maxRadiusKm = 0.7,
    double turns = 3.2,
    int points = 120,
  }) {
    return List.generate(points + 1, (i) {
      final t = i / points;
      final angle = t * turns * 2 * math.pi;
      final r = maxRadiusKm * (1 - t * 0.82);
      return offset(center, r * math.cos(angle), r * math.sin(angle) * 0.85);
    });
  }

  /// A river-path meander — long, low-amplitude sine along a bearing.
  static List<LatLng> meander(
    LatLng start, {
    double lengthKm = 5.2,
    double amplitudeKm = 0.42,
    double bearingDeg = 100,
    double waves = 2.6,
    int points = 110,
  }) {
    final theta = bearingDeg * math.pi / 180;
    return List.generate(points + 1, (i) {
      final t = i / points;
      final along = t * lengthKm;
      final side =
          amplitudeKm * math.sin(t * waves * 2 * math.pi) * (1 - 0.3 * t);
      return offset(
        start,
        along * math.cos(theta) - side * math.sin(theta),
        along * math.sin(theta) + side * math.cos(theta),
      );
    });
  }

  /// Right-angle turns through city blocks.
  static List<LatLng> cityBlocks(
    LatLng start, {
    double blockKm = 0.32,
    int blocks = 7,
    int seed = 4,
  }) {
    final rng = _Rng(seed);
    final route = <LatLng>[];
    var east = 0.0;
    var north = 0.0;
    route.add(offset(start, east, north));
    for (var i = 0; i < blocks; i++) {
      final runEast = blockKm * (1 + rng.next());
      final runNorth = blockKm * (0.7 + rng.next());
      for (var s = 1; s <= 6; s++) {
        route.add(offset(start, east + runEast * s / 6, north));
      }
      east += runEast;
      for (var s = 1; s <= 6; s++) {
        route.add(offset(start, east, north + runNorth * s / 6));
      }
      north += runNorth;
    }
    // Return leg down the long avenue.
    for (var s = 1; s <= 18; s++) {
      route.add(offset(start, east * (1 - s / 18), north * (1 - s / 18) + 0.06));
    }
    return route;
  }

  /// A shoreline crescent.
  static List<LatLng> crescent(
    LatLng center, {
    double radiusKm = 1.6,
    double sweepDeg = 210,
    double startDeg = 200,
    int points = 80,
  }) {
    return List.generate(points + 1, (i) {
      final t = i / points;
      final angle = (startDeg + sweepDeg * t) * math.pi / 180;
      final r = radiusKm * (0.86 + 0.14 * math.sin(t * math.pi * 3));
      return offset(center, r * math.cos(angle), r * math.sin(angle));
    });
  }

  /// Picks [count] points spread evenly along a route — used to place seeded
  /// prayer waypoints so they always land *on* the trail.
  static List<LatLng> along(List<LatLng> route, int count) {
    if (route.isEmpty || count <= 0) return const [];
    return List.generate(count, (i) {
      final position = (i + 1) / (count + 1);
      return route[(route.length * position).floor().clamp(0, route.length - 1)];
    });
  }
}

/// A tiny linear congruential generator. `dart:math`'s Random is seedable too,
/// but this keeps the sequence identical across Dart versions, which matters
/// when the seeded fixtures are what reviewers look at.
class _Rng {
  _Rng(int seed) : _state = (seed * 2654435761) & 0x7FFFFFFF;
  int _state;

  double next() {
    _state = (_state * 1103515245 + 12345) & 0x7FFFFFFF;
    return _state / 0x7FFFFFFF;
  }

  double symmetric() => next() * 2 - 1;
}
