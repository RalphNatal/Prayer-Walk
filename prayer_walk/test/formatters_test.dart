import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_walk/src/core/utils/formatters.dart';

void main() {
  group('distance', () {
    test('stays in metres below a kilometre', () {
      expect(Fmt.distance(640), '640 m');
      expect(Fmt.distanceUnit(640), 'm');
    });

    test('uses two decimals under 10 km and one above', () {
      expect(Fmt.distance(8423), '8.42 km');
      expect(Fmt.distance(12437), '12.4 km');
    });
  });

  group('duration', () {
    test('drops the hour field when there is none', () {
      expect(Fmt.duration(const Duration(minutes: 48, seconds: 20)), '48:20');
    });

    test('zero-pads minutes and seconds once hours appear', () {
      expect(
        Fmt.duration(const Duration(hours: 1, minutes: 4, seconds: 2)),
        '1:04:02',
      );
    });
  });

  group('pace', () {
    test('is minutes per kilometre', () {
      // 5 km in 33:30 -> 6:42 per km.
      expect(Fmt.pace(5000, const Duration(minutes: 33, seconds: 30)), '6:42');
    });

    test('is undefined for a walk that has barely started', () {
      expect(Fmt.pace(4, const Duration(seconds: 3)), '—');
      expect(Fmt.pace(1000, Duration.zero), '—');
    });
  });

  group('plural', () {
    test('agrees with the count', () {
      expect(Fmt.plural(1, 'intention'), '1 intention');
      expect(Fmt.plural(3, 'intention'), '3 intentions');
    });

    test('takes an irregular plural', () {
      expect(Fmt.plural(2, 'person', 'people'), '2 people');
    });
  });

  group('relativeTime', () {
    final now = DateTime(2026, 3, 4, 12);

    test('reads in the units a person would use', () {
      expect(Fmt.relativeTime(now.subtract(const Duration(seconds: 20)), now: now), 'Just now');
      expect(Fmt.relativeTime(now.subtract(const Duration(minutes: 12)), now: now), '12m ago');
      expect(Fmt.relativeTime(now.subtract(const Duration(hours: 3)), now: now), '3h ago');
      expect(Fmt.relativeTime(now.subtract(const Duration(days: 1)), now: now), 'Yesterday');
    });

    test('falls back to a date beyond a week', () {
      expect(
        Fmt.relativeTime(now.subtract(const Duration(days: 20)), now: now),
        '12 Feb',
      );
    });
  });
}
