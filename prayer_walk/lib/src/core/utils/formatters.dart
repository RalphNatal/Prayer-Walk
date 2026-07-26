import 'package:intl/intl.dart';

/// Formatting for every number and date the member sees.
///
/// Distance is metric throughout this phase; a unit preference is a Phase 2
/// profile setting.
abstract final class Fmt {
  // ------------------------------------------------------------- distance ---

  /// `8.42 km` below 10 km, `12.4 km` above, `640 m` under a kilometre.
  static String distance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    final km = meters / 1000;
    return '${km.toStringAsFixed(km < 10 ? 2 : 1)} km';
  }

  static String distanceValue(double meters) {
    if (meters < 1000) return meters.round().toString();
    final km = meters / 1000;
    return km.toStringAsFixed(km < 10 ? 2 : 1);
  }

  static String distanceUnit(double meters) => meters < 1000 ? 'm' : 'km';

  // ------------------------------------------------------------- duration ---

  /// `1:04:12` with hours, `48:20` without. Always zero-padded after the first
  /// field so the readout keeps a stable width.
  static String duration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  }

  /// `1h 04m` / `48m` — for captions, where seconds are noise.
  static String durationShort(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m}m';
  }

  // ----------------------------------------------------------------- pace ---

  /// Minutes per kilometre, `6:42 /km`. Returns an em dash when undefined.
  static String pace(double meters, Duration elapsed) {
    if (meters < 10 || elapsed.inSeconds == 0) return '—';
    final secondsPerKm = elapsed.inSeconds / (meters / 1000);
    final m = secondsPerKm ~/ 60;
    final s = (secondsPerKm % 60).round();
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// Kilometres per hour, for rides.
  static String speed(double meters, Duration elapsed) {
    if (elapsed.inSeconds == 0) return '—';
    final kmh = (meters / 1000) / (elapsed.inSeconds / 3600);
    return kmh.toStringAsFixed(1);
  }

  static String elevation(double meters) => '${meters.round()} m';

  // ----------------------------------------------------------------- time ---

  /// `Just now`, `12m ago`, `3h ago`, `Yesterday`, `4 Mar`.
  static String relativeTime(DateTime when, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final diff = reference.difference(when);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return DateFormat('d MMM').format(when);
  }

  /// `Tue 4 Mar · 5:40 am`
  static String dayAndTime(DateTime when) =>
      DateFormat("EEE d MMM · h:mm a").format(when).replaceAll('AM', 'am').replaceAll('PM', 'pm');

  static String dayMonth(DateTime when) => DateFormat('d MMM').format(when);

  static String dayMonthYear(DateTime when) => DateFormat('d MMM yyyy').format(when);

  /// `1,284` — grouped so admin counts stay readable.
  static String count(int value) => NumberFormat.decimalPattern().format(value);

  /// `2 prayers` / `1 prayer`
  static String plural(int n, String singular, [String? plural]) =>
      n == 1 ? '$n $singular' : '$n ${plural ?? '${singular}s'}';
}
