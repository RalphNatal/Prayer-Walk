import 'package:latlong2/latlong.dart';

/// One position reading, reduced to what the app needs — and deliberately
/// plugin-free so the repository interface and the widgets can speak in it
/// without anyone above [LocationService] importing `geolocator`.
///
/// The accuracy and the timestamp are not decoration. A position without them
/// cannot be judged, and a position that cannot be judged gets drawn at full
/// confidence whether or not it deserves it — which is exactly how a cached fix
/// from another city ends up presented as "you are here".
class LocationFix {
  const LocationFix({
    required this.point,
    required this.accuracyMeters,
    required this.altitudeMeters,
    required this.timestamp,
  });

  final LatLng point;

  /// Radius of 68% confidence, in metres. Bigger is worse.
  ///
  /// Some platforms report `0` or a negative number to mean "unknown" rather
  /// than "perfect" — [hasAccuracy] is the guard against reading it the
  /// flattering way.
  final double accuracyMeters;

  /// Metres above the WGS-84 ellipsoid. Notoriously noisy on phones — treat
  /// anything derived from it as approximate.
  final double altitudeMeters;

  /// When the platform took the reading. Compared against the wall clock in
  /// UTC, because a device fix is timestamped in UTC and the local clock is
  /// not — subtracting the two directly would be wrong by the offset, which in
  /// this app's own timezone is a silent eight hours.
  final DateTime timestamp;

  bool get hasAccuracy => accuracyMeters > 0;

  Duration get age => DateTime.now().toUtc().difference(timestamp.toUtc());

  /// How this fix should be described to the person looking at it.
  LocationSignal get signal {
    if (!hasAccuracy) return LocationSignal.unknown;
    if (accuracyMeters <= LocationQuality.goodAccuracyMeters) {
      return LocationSignal.sharp;
    }
    if (accuracyMeters <= LocationQuality.maxDisplayAccuracyMeters) {
      return LocationSignal.fair;
    }
    return LocationSignal.weak;
  }

  /// Fresh enough and tight enough to show as the person's current position.
  bool get isDisplayable =>
      hasAccuracy &&
      accuracyMeters <= LocationQuality.maxDisplayAccuracyMeters &&
      age <= LocationQuality.maxFixAgeForDisplay;

  /// A one-line diagnostic: `<lat>, <lng> ±8m, 0s old`.
  String describe() =>
      '${point.latitude.toStringAsFixed(6)}, '
      '${point.longitude.toStringAsFixed(6)} '
      '${hasAccuracy ? '±${accuracyMeters.round()}m' : '±unknown'}, '
      '${age.inSeconds}s old';
}

/// Why the app can and can't read the device's position, in the shapes the UI
/// actually has to act on differently.
enum LocationAccess {
  /// Precise location. Good to record.
  granted,

  /// Permission was given, but only the *approximate* variant Android 12+ and
  /// iOS 14+ offer. That is accurate to somewhere between one and ten
  /// kilometres — enough to know the city, useless for tracing a walk.
  ///
  /// Recording is still allowed, because a rough trace the walker was warned
  /// about beats no walk at all. Silently drawing it as a real route is not.
  grantedApproximate,

  /// Denied this time. Asking again is allowed — the button can retry.
  denied,

  /// Denied permanently (or restricted). Only Settings can undo it.
  deniedForever,

  /// Location is switched off device-wide. Not a permission problem.
  serviceDisabled;

  /// The app may open the position stream.
  bool get canRecord => this == granted || this == grantedApproximate;

  /// The fix that comes back can be trusted to metres rather than kilometres.
  bool get isPrecise => this == granted;
}

/// Whether the app may keep reading position once it is no longer the thing on
/// screen — Android's "Allow all the time", iOS's Always.
///
/// Deliberately separate from [LocationAccess] rather than another value on it,
/// because it is not another rung on the same ladder. A recording does not need
/// this: on Android the foreground service carries the walk, on iOS the
/// `location` background mode does, and both run on the ordinary when-in-use
/// grant. What this adds is survival across a process restart, which is the
/// difference between an hour's walk recovered and an hour's walk offered back
/// as a draft. So it is asked for once, late, and a refusal changes nothing the
/// walker will notice on an ordinary walk.
enum BackgroundLocationAccess {
  /// Granted. The service can be restarted by the system and keep reading.
  granted,

  /// Asked and refused, or never asked. Recording still works.
  denied,

  /// Refused in a way only the system settings app can undo. On Android 11+
  /// this is the *ordinary* outcome of asking: the platform stopped showing a
  /// dialog for background location and moved it to a settings page, so the
  /// only honest next step is to offer that page.
  deniedForever,

  /// Nothing to ask for here — iOS, older Android, desktop, a test with no
  /// plugins. Never shown to anyone.
  notApplicable;

  /// Whether there is any point offering the walker a way to change this.
  bool get isActionable => this == denied || this == deniedForever;
}

/// Everything one look at the device produced: how much access we have, and
/// the fix that access yielded.
///
/// The two travel together because the screen needs both to say anything true.
/// A null [fix] means very different things under [LocationAccess.denied] and
/// under [LocationAccess.granted] — "you said no" versus "still looking" — and
/// a caller that only receives the position cannot tell them apart.
class LocationReading {
  const LocationReading({required this.access, this.fix});

  final LocationAccess access;

  /// Null when there is no position worth showing: permission refused,
  /// location switched off, or nothing yet that passed [LocationFix.isDisplayable].
  final LocationFix? fix;

  bool get isApproximate => access == LocationAccess.grantedApproximate;

  bool get hasFix => fix != null;
}

/// The accuracy radius, translated into the three words a walker can act on.
enum LocationSignal {
  sharp('Sharp'),
  fair('Fair'),
  weak('Weak'),
  unknown('No signal');

  const LocationSignal(this.label);

  final String label;
}

/// Every threshold that decides whether a position is good enough, in one
/// place.
///
/// These used to be split between the location service and the recorder, which
/// meant two numbers that could drift apart and no single answer to "how
/// accurate does a fix have to be?". They are different numbers because they
/// answer different questions — showing a dot is a lower bar than measuring a
/// distance — but they live together so the relationship between them stays
/// visible.
abstract final class LocationQuality {
  /// Older than this and a cached fix is history, not a position. Two minutes
  /// of walking is roughly 150 m; beyond that the dot is a lie.
  static const Duration maxFixAgeForDisplay = Duration(minutes: 2);

  /// Wider than this and we would be drawing a dot that could be anywhere in a
  /// city block. Show the locating state instead.
  static const double maxDisplayAccuracyMeters = 50;

  /// Recording-grade. A GNSS lock in the open reaches this in seconds; a
  /// network/cell fix never does.
  static const double goodAccuracyMeters = 20;

  /// Wider than this and a fix is noise, not a position — it is dropped from
  /// the route entirely rather than smoothed.
  static const double maxRecordingAccuracyMeters = 25;

  /// Below this, a "movement" is GPS jitter. The platform's `distanceFilter`
  /// already screens most of it; this catches the rest.
  static const double minStepMeters = 3;

  /// GPS altitude wanders by several metres at rest. Only climbs above this
  /// count toward the gain.
  static const double minClimbMeters = 1.5;

  /// How long a recording will hold its first point back waiting for the
  /// signal to sharpen to [goodAccuracyMeters]. Past this the walk starts on
  /// whatever the device has, because refusing to record at all is worse than
  /// recording a slightly soft opening.
  static const Duration warmUpWindow = Duration(seconds: 20);

  /// A cold start indoors can take well over fifteen seconds. Being impatient
  /// here is what pushes the one-shot lookup onto its stale-cache fallback.
  static const Duration oneShotTimeout = Duration(seconds: 30);
}
