import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:prayer_walk/src/features/privacy/domain/privacy_zone.dart';
import 'package:prayer_walk/src/features/privacy/domain/zone_trimming.dart';

/// The zone-trimming rule.
///
/// ⚠️ **What this file does not test.** The trimming that protects anybody
/// happens in Postgres, in `activity_trace_for_viewer`, before a coordinate is
/// serialised — a Dart test cannot reach it, and a Dart implementation could
/// not replace it, because a client that received the real points and declined
/// to draw them would already have been handed the address.
///
/// What it does test is the rule those two implementations share, so that the
/// owner's "what others will see" preview on the summary screen cannot quietly
/// disagree with what the server actually sends. If the SQL changes, these
/// should fail. The three-account check in the README is what proves the
/// server side.

/// A doorway, and the street it is on. Coordinates are Metro Manila so the
/// haversine is exercised at a real latitude rather than at the equator, where
/// a longitude error would cancel out.
const _home = LatLng(14.5794, 121.0359);

PrivacyZone _zone({
  LatLng centre = _home,
  int radius = PrivacyZone.defaultRadiusMeters,
}) => PrivacyZone(
  id: 'z1',
  label: 'Home',
  centre: centre,
  radiusMeters: radius,
  createdAt: DateTime(2026, 7, 1),
);

/// A point [metres] due north of [from]. One degree of latitude is ~111.32 km
/// everywhere, so this is exact enough to place a fix either side of a
/// 200-metre boundary without ambiguity.
LatLng _north(LatLng from, double metres) =>
    LatLng(from.latitude + metres / 111320, from.longitude);

void main() {
  group('metresBetween', () {
    test('is zero for a point and itself', () {
      expect(metresBetween(_home, _home), closeTo(0, 0.001));
    });

    test('measures a known northward offset', () {
      expect(metresBetween(_home, _north(_home, 500)), closeTo(500, 1));
    });

    test('is symmetric', () {
      final away = _north(_home, 1200);
      expect(
        metresBetween(_home, away),
        closeTo(metresBetween(away, _home), 0.001),
      );
    });
  });

  group('trimRoute', () {
    test('leaves a route alone when there are no zones', () {
      final route = [_home, _north(_home, 500), _north(_home, 1000)];
      final trimmed = trimRoute(route, const []);

      expect(trimmed.route, route);
      expect(trimmed.trimmed, isFalse);
      expect(trimmed.removedFromStart, 0);
      expect(trimmed.removedFromEnd, 0);
    });

    test('drops the points at the start that fall inside a zone', () {
      // Two fixes inside the 200 m circle, then away up the road.
      final route = [
        _home,
        _north(_home, 100),
        _north(_home, 400),
        _north(_home, 900),
      ];
      final trimmed = trimRoute(route, [_zone()]);

      expect(trimmed.removedFromStart, 2);
      expect(trimmed.removedFromEnd, 0);
      expect(trimmed.trimmed, isTrue);
      expect(trimmed.route.first, _north(_home, 400));
    });

    test('drops the points at the end too — the walk that comes home', () {
      final route = [
        _home,
        _north(_home, 150),
        _north(_home, 800),
        _north(_home, 150),
        _home,
      ];
      final trimmed = trimRoute(route, [_zone()]);

      expect(trimmed.removedFromStart, 2);
      expect(trimmed.removedFromEnd, 2);
      expect(trimmed.route, [_north(_home, 800)]);
    });

    test(
      'keeps a point inside a zone when it is in the middle of the route',
      () {
        // Deliberate: cutting a hole out of the middle would make the map draw
        // a straight line across the gap, whose two ends sit on the circle's
        // edge. A chord locates a centre far more precisely than the honest
        // curve running past it. See the note on `trimRoute`.
        final far = _north(_home, 3000);
        final route = [far, _home, _north(far, 500)];
        final trimmed = trimRoute(route, [_zone()]);

        expect(trimmed.trimmed, isFalse);
        expect(trimmed.route, route);
        expect(trimmed.route, contains(_home));
      },
    );

    test('returns nothing for a walk that never left the zone', () {
      final route = [_home, _north(_home, 50), _north(_home, 120), _home];
      final trimmed = trimRoute(route, [_zone()]);

      expect(trimmed.route, isEmpty);
      expect(trimmed.trimmed, isTrue);
    });

    test('a point exactly on the boundary is inside', () {
      // `<=` in both implementations. The boundary belongs to the zone, which
      // is the direction that hides one more fix rather than one fewer.
      final route = [
        _north(_home, PrivacyZone.defaultRadiusMeters.toDouble()),
        _north(_home, 2000),
      ];
      final trimmed = trimRoute(route, [_zone()]);

      expect(trimmed.removedFromStart, 1);
    });

    test('honours more than one zone — home at one end, work at the other', () {
      final work = _north(_home, 5000);
      final route = [
        _home,
        _north(_home, 1500),
        _north(_home, 3000),
        work,
      ];
      final trimmed = trimRoute(route, [
        _zone(),
        _zone(centre: work, radius: 300),
      ]);

      expect(trimmed.removedFromStart, 1);
      expect(trimmed.removedFromEnd, 1);
      expect(trimmed.route, [_north(_home, 1500), _north(_home, 3000)]);
    });

    test('a wider radius trims more of the same walk', () {
      final route = [
        _home,
        _north(_home, 300),
        _north(_home, 700),
        _north(_home, 2500),
      ];

      expect(trimRoute(route, [_zone()]).removedFromStart, 1);
      expect(trimRoute(route, [_zone(radius: 500)]).removedFromStart, 2);
      expect(trimRoute(route, [_zone(radius: 1000)]).removedFromStart, 3);
    });

    test('an empty route survives being trimmed', () {
      final trimmed = trimRoute(const [], [_zone()]);

      expect(trimmed.route, isEmpty);
      expect(trimmed.trimmed, isFalse);
    });
  });

  group('withoutPointsInZones', () {
    test('drops a waypoint inside a zone wherever it sits in the list', () {
      // Waypoints are filtered wholesale rather than from the ends: a waypoint
      // is a point and not a segment, so removing one from the middle leaves no
      // line behind to give it away.
      final points = [_home, _north(_home, 900), _north(_home, 100)];
      final kept = withoutPointsInZones(points, [_zone()], (p) => p);

      expect(kept, [_north(_home, 900)]);
    });

    test('keeps everything when there are no zones', () {
      final points = [_home, _north(_home, 900)];
      expect(withoutPointsInZones(points, const [], (p) => p), points);
    });
  });
}
