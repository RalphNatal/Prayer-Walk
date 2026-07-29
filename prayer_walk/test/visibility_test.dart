import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_walk/src/features/activity/data/activity_row_mapper.dart';
import 'package:prayer_walk/src/features/discovery/data/supabase_discovery_repository.dart';
import 'package:prayer_walk/src/features/privacy/data/supabase_privacy_repository.dart';
import 'package:prayer_walk/src/features/privacy/domain/activity_visibility.dart';
import 'package:prayer_walk/src/features/privacy/domain/privacy_zone.dart';

/// The visibility model, from the app's side of the wire.
///
/// ⚠️ The boundary is the SELECT policy on `activities` and the predicate
/// `pw_can_view_activity` behind it — see
/// `20260728090000_visibility_rls_and_reads.sql`. Nothing in Dart decides who
/// may read a walk, and a test here could not prove that it does. What these
/// assert is the half the app is responsible for: that the wire values map to
/// the right setting, that an unfamiliar one fails towards *less* exposure, and
/// that a trimmed card arrives carrying the flag that makes the map say so.
///
/// Proving the policy itself takes three accounts and a direct query as a
/// non-follower. The README says so, and says why the UI hiding a walk is not
/// the test.

Map<String, dynamic> _authorRow() => {
  'id': '3f0c8b7a-1111-4111-8111-111111111111',
  'full_name': 'Ana Villanueva',
  'avatar_url': null,
  'handle': 'anav',
  'bio': '',
  'parish': 'Our Lady of Peace, Antipolo',
  'role': 'member',
  'status': 'active',
  'created_at': '2026-01-04T09:15:00+00:00',
};

/// An `activity_card`, as the rewritten read functions return it.
Map<String, dynamic> _cardRow({
  String visibility = 'followers',
  bool routeTrimmed = false,
}) => {
  'id': '9a1d4c66-2222-4222-8222-222222222222',
  'user_id': '3f0c8b7a-1111-4111-8111-111111111111',
  'type': 'walk',
  'title': 'Evening round',
  'started_at': '2026-07-26T22:10:00+00:00',
  'duration_seconds': 2400,
  'distance_meters': 4200.0,
  'elevation_gain_meters': 40.0,
  'route': [
    [14.5878, 121.1760],
    [14.5881, 121.1768],
  ],
  'waypoints': <dynamic>[],
  'intentions': <dynamic>[],
  'note': '',
  'place_name': 'Antipolo',
  'visibility': visibility,
  'route_trimmed': routeTrimmed,
  'created_at': '2026-07-26T23:00:00+00:00',
  'author': _authorRow(),
  'encouragement_count': 0,
  'comment_count': 0,
  'encouraged_by_viewer': false,
};

void main() {
  group('ActivityVisibility', () {
    test('maps each wire value to its setting', () {
      expect(
        ActivityVisibility.fromWire('private'),
        ActivityVisibility.private,
      );
      expect(
        ActivityVisibility.fromWire('followers'),
        ActivityVisibility.followers,
      );
      expect(ActivityVisibility.fromWire('public'), ActivityVisibility.public);
    });

    test('an unknown value fails towards the most private setting', () {
      // The check constraint makes this unreachable today. It matters if a
      // later migration adds a fourth value and an older build reads it: a
      // build guessing at a setting it does not know must guess in the
      // direction that shows a walk to fewer people, never more.
      expect(ActivityVisibility.fromWire('parish'), ActivityVisibility.private);
      expect(ActivityVisibility.fromWire(null), ActivityVisibility.private);
      expect(ActivityVisibility.fromWire(''), ActivityVisibility.private);
    });

    test('the standing default is followers, not public', () {
      // The whole B1 argument in one assertion. A member opts into a wider
      // audience; they are never opted in by a default, a migration or a
      // backfill.
      expect(ActivityVisibility.standard, ActivityVisibility.followers);
      expect(ActivityVisibility.standard.reachesStrangers, isFalse);
    });

    test('only public reaches strangers', () {
      expect(ActivityVisibility.private.reachesStrangers, isFalse);
      expect(ActivityVisibility.followers.reachesStrangers, isFalse);
      expect(ActivityVisibility.public.reachesStrangers, isTrue);
    });

    test('every option describes its own consequence', () {
      // The picker shows these next to the radio. An option with no sentence is
      // an option somebody chooses without knowing what it does — which on this
      // particular setting happens outdoors, to a real address.
      for (final option in ActivityVisibility.values) {
        expect(option.label, isNotEmpty);
        expect(option.description, isNotEmpty);
      }
    });
  });

  group('activity_card rows', () {
    test('carry the walk\'s visibility', () {
      expect(
        activityFromRow(_cardRow(visibility: 'public')).visibility,
        ActivityVisibility.public,
      );
      expect(
        activityFromRow(_cardRow(visibility: 'private')).visibility,
        ActivityVisibility.private,
      );
    });

    test('carry whether the server shortened the trace', () {
      expect(activityFromRow(_cardRow()).routeTrimmed, isFalse);
      expect(
        activityFromRow(_cardRow(routeTrimmed: true)).routeTrimmed,
        isTrue,
      );
    });

    test('a plain activities row reads as untrimmed', () {
      // A plain `activities` row is read straight from the table by its owner,
      // who is never trimmed — so the absent key means "your own whole walk".
      final row = _cardRow()..remove('route_trimmed');
      expect(activityFromRow(row).routeTrimmed, isFalse);
    });

    test('a trimmed card keeps the full recorded distance', () {
      // The distance is deliberately not recomputed to match the shortened
      // line. Both halves of that decision are asserted here: the number stays
      // whole, and the flag that makes the card explain it is set.
      final trimmed = activityFromRow(_cardRow(routeTrimmed: true));
      expect(trimmed.distanceMeters, 4200.0);
      expect(trimmed.routeTrimmed, isTrue);
    });
  });

  group('privacy zone rows', () {
    test('map centre and radius', () {
      final zone = privacyZoneFromRow({
        'id': 'z1',
        'label': ' Home ',
        'lat': 14.5794,
        'lng': 121.0359,
        'radius_meters': 250,
        'created_at': '2026-07-01T00:00:00+00:00',
      });

      expect(zone.label, 'Home');
      expect(zone.centre.latitude, 14.5794);
      expect(zone.radiusMeters, 250);
    });

    test('a row with no radius falls back to the default, not to zero', () {
      // A zero radius is a zone that hides nothing while telling its owner they
      // are covered, which is the worst state this feature has.
      final zone = privacyZoneFromRow({
        'id': 'z1',
        'label': 'Home',
        'lat': 14.5794,
        'lng': 121.0359,
        'created_at': '2026-07-01T00:00:00+00:00',
      });

      expect(zone.radiusMeters, PrivacyZone.defaultRadiusMeters);
    });
  });

  group('member_card rows', () {
    test('map the nested profile, follow state and last visible walk', () {
      final cards = memberCardsFromRows([
        {
          'profile': _authorRow(),
          'is_following': true,
          'follower_count': 12,
          'last_walked_at': '2026-07-26T22:10:00+00:00',
        },
      ]);

      expect(cards.single.profile.displayName, 'Ana Villanueva');
      expect(cards.single.isFollowing, isTrue);
      expect(cards.single.followerCount, 12);
      expect(cards.single.lastWalkedAt, isNotNull);
    });

    test('a member with no visible walks has a null last walk', () {
      // Null because RLS removed the rows, not because they have been idle —
      // `search_members` counts only what the viewer may see. The tile reads it
      // as "nothing to show" rather than as "walked never".
      final cards = memberCardsFromRows([
        {
          'profile': _authorRow(),
          'is_following': false,
          'follower_count': 0,
          'last_walked_at': null,
        },
      ]);

      expect(cards.single.lastWalkedAt, isNull);
      expect(cards.single.isFollowing, isFalse);
    });
  });
}
