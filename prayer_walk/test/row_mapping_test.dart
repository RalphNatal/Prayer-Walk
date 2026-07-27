import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_walk/src/features/activity/data/activity_row_mapper.dart';
import 'package:prayer_walk/src/features/activity/domain/activity.dart';
import 'package:prayer_walk/src/features/feed/data/supabase_feed_repository.dart';
import 'package:prayer_walk/src/features/profile/data/profile_row_mapper.dart';

/// The mapping between a Postgres row and the domain, tested without a
/// Postgres. Everything below is the shape the SQL functions actually return —
/// an `activity_card` with its nested author, and a `member_stats` row.

Map<String, dynamic> _authorRow({String? fullName, String? handle}) => {
  'id': '3f0c8b7a-1111-4111-8111-111111111111',
  'full_name': fullName,
  'avatar_url': null,
  'handle': handle,
  'bio': 'Nurse. Night shift, morning hills.',
  'parish': 'Our Lady of Peace, Antipolo',
  'role': 'member',
  'status': 'active',
  'created_at': '2026-01-04T09:15:00+00:00',
};

Map<String, dynamic> _cardRow({
  int encouragements = 0,
  int comments = 0,
  bool encouraged = false,
}) => {
  'id': '9a1d4c66-2222-4222-8222-222222222222',
  'user_id': '3f0c8b7a-1111-4111-8111-111111111111',
  'type': 'hike',
  'title': 'Antipolo climb',
  'started_at': '2026-07-26T22:10:00+00:00',
  'duration_seconds': 5400,
  'distance_meters': 8200.5,
  'elevation_gain_meters': 310.0,
  'route': [
    [14.5878, 121.1760],
    [14.5881, 121.1768],
  ],
  'waypoints': [
    {
      'lat': 14.5879,
      'lng': 121.1762,
      'kind': 'gratitude',
      'label': 'The bend',
      'note': '',
      'elapsed_seconds': 600,
    },
  ],
  'intentions': [
    {'text': 'For Lola Iding', 'category': 'healing'},
  ],
  'note': 'Rain the whole way up.',
  'place_name': ' Antipolo ',
  'created_at': '2026-07-26T23:00:00+00:00',
  'author': _authorRow(fullName: 'Ana Villanueva', handle: 'anav'),
  'encouragement_count': encouragements,
  'comment_count': comments,
  'encouraged_by_viewer': encouraged,
};

void main() {
  group('userProfileFromRow', () {
    test('maps the row a profile select and a feed author both return', () {
      final profile = userProfileFromRow(
        _authorRow(fullName: 'Ana Villanueva', handle: '@anav'),
      );

      expect(profile.displayName, 'Ana Villanueva');
      expect(profile.handle, '@anav');
      expect(profile.parish, 'Our Lady of Peace, Antipolo');
      expect(profile.initials, 'AV');
    });

    test('a handle stored without the @ still reads with one', () {
      expect(userProfileFromRow(_authorRow(handle: 'anav')).handle, '@anav');
    });

    test('a new account with no name or handle gets an honest placeholder', () {
      final profile = userProfileFromRow(_authorRow(fullName: '', handle: ''));

      expect(profile.displayName, 'Walker');
      expect(profile.handle, '@member');
    });

    test('a name with no handle derives one rather than inventing a stored one', () {
      final profile = userProfileFromRow(
        _authorRow(fullName: 'Ana Villanueva', handle: null),
      );

      expect(profile.handle, '@anavillanueva');
    });

    test('the avatar tint is stable for an id and independent of the name', () {
      final first = userProfileFromRow(_authorRow(fullName: 'Ana Villanueva'));
      final renamed = userProfileFromRow(_authorRow(fullName: 'A. Villanueva'));

      expect(first.accentIndex, renamed.accentIndex);
      expect(first.accentIndex, inInclusiveRange(0, 5));
    });

    test('stats and counts default to zero, never to a guess', () {
      final profile = userProfileFromRow(_authorRow());

      expect(profile.stats.activityCount, 0);
      expect(profile.stats.totalDuration, Duration.zero);
      expect(profile.followerCount, 0);
      expect(profile.followingCount, 0);
    });
  });

  group('lifetimeStatsFromRow', () {
    test('seconds come back as a Duration', () {
      final stats = lifetimeStatsFromRow({
        'total_distance_meters': 1284300.0,
        'total_duration_seconds': 7725,
        'activity_count': 186,
        'intention_count': 341,
        'streak_days': 12,
      });

      expect(stats.totalDistanceMeters, 1284300.0);
      expect(stats.totalDuration, const Duration(hours: 2, minutes: 8, seconds: 45));
      expect(stats.activityCount, 186);
      expect(stats.intentionCount, 341);
      expect(stats.streakDays, 12);
    });

    test('no stats row is zeros, not a crash', () {
      expect(lifetimeStatsFromRow(null).activityCount, 0);
      expect(lifetimeStatsFromRow(null).streakDays, 0);
    });
  });

  group('activityFromRow', () {
    test('decodes the JSONB columns and trims the place name', () {
      final activity = activityFromRow(_cardRow());

      expect(activity.type, ActivityType.hike);
      expect(activity.duration, const Duration(minutes: 90));
      expect(activity.route, hasLength(2));
      expect(activity.route.first.latitude, closeTo(14.5878, 1e-6));
      expect(activity.waypoints.single.kind, WaypointKind.gratitude);
      expect(activity.waypoints.single.elapsed, const Duration(minutes: 10));
      expect(activity.intentions.single.category, PrayerCategory.healing);
      expect(activity.placeName, 'Antipolo');
    });

    test('carries the social counts the card row brings with it', () {
      final activity = activityFromRow(
        _cardRow(encouragements: 3, comments: 2, encouraged: true),
      );

      expect(activity.encouragementCount, 3);
      expect(activity.commentCount, 2);
      expect(activity.encouragedByViewer, isTrue);
    });

    test('a plain activities row reports no encouragement rather than guessing', () {
      final row = Map<String, dynamic>.from(_cardRow())
        ..remove('encouragement_count')
        ..remove('comment_count')
        ..remove('encouraged_by_viewer');

      final activity = activityFromRow(row);

      expect(activity.encouragementCount, 0);
      expect(activity.commentCount, 0);
      expect(activity.encouragedByViewer, isFalse);
    });

    test('a row with no route or waypoints is valid, not empty-ish', () {
      final row = Map<String, dynamic>.from(_cardRow())
        ..['route'] = <dynamic>[]
        ..['waypoints'] = <dynamic>[]
        ..['intentions'] = <dynamic>[]
        ..['place_name'] = null;

      final activity = activityFromRow(row);

      expect(activity.route, isEmpty);
      expect(activity.waypoints, isEmpty);
      expect(activity.placeName, isNull);
    });
  });

  group('feedEntriesFromRows', () {
    test('an empty feed maps to an empty list, not an error', () {
      expect(feedEntriesFromRows(const []), isEmpty);
    });

    test('joins each activity to its author in one pass', () {
      final entries = feedEntriesFromRows([
        _cardRow(encouragements: 1, comments: 4, encouraged: true),
      ]);

      expect(entries, hasLength(1));
      expect(entries.single.author.displayName, 'Ana Villanueva');
      expect(entries.single.activity.title, 'Antipolo climb');
      expect(entries.single.activity.userId, entries.single.author.id);
      expect(entries.single.activity.commentCount, 4);
      expect(entries.single.activity.encouragedByViewer, isTrue);
    });
  });
}
