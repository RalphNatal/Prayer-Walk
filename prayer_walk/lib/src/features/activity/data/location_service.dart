import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `AndroidSettings`, `AppleSettings` and `ActivityType` come through this one
// import — geolocator 14 re-exports the platform packages, so the settings
// types are available without depending on `geolocator_android` /
// `geolocator_apple` directly.
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/utils/app_logger.dart';
import '../domain/location_fix.dart';

export '../domain/location_fix.dart';

/// The single file that imports `geolocator`.
///
/// Everything above it speaks in [LatLng], [LocationAccess] and a stream of
/// [LocationFix]. Swapping the plugin means rewriting this file and nothing
/// else — the same bargain [RouteMapView] makes with `flutter_map`.
///
/// The platform-specific settings types are used here too, and only here:
/// `AndroidSettings` and `AppleSettings` are the difference between the Fused
/// Location Provider and a raw cell fix, and neither name is allowed to escape
/// this file.
///
/// Foreground only this phase: no background service, no `Always` permission.
class LocationService {
  LocationService();

  static const _tag = 'PW-LOC';

  /// iOS shows a system prompt for temporary full accuracy, so it is asked at
  /// most once per app run. Asking on every `ensureAccess` would turn a
  /// re-centre tap into a dialog.
  bool _askedForTemporaryAccuracy = false;

  /// Checks the service and the permission, asking for the latter if it has
  /// not been decided yet, and then checks whether what was granted is
  /// *precise*. Safe to call repeatedly — a granted precise permission
  /// short-circuits without showing a prompt.
  Future<LocationAccess> ensureAccess() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.serviceDisabled;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return switch (permission) {
      // A grant is not the end of the question: the OS may have handed over
      // approximate location, which looks identical from here unless asked.
      LocationPermission.always ||
      LocationPermission.whileInUse => await _resolvePrecision(),
      LocationPermission.deniedForever => LocationAccess.deniedForever,
      // `unableToDetermine` is treated as a soft denial: retryable, since it
      // usually means the platform hasn't answered yet rather than "no".
      LocationPermission.denied ||
      LocationPermission.unableToDetermine => LocationAccess.denied,
    };
  }

  /// Distinguishes precise from approximate, and on iOS tries to upgrade.
  ///
  /// Android has no equivalent of `requestTemporaryFullAccuracy` — precise
  /// location there can only be turned on by the person, in system settings —
  /// so the Android path reports the reduced state and lets the UI offer the
  /// settings route.
  Future<LocationAccess> _resolvePrecision() async {
    LocationAccuracyStatus status;
    try {
      status = await Geolocator.getLocationAccuracy();
    } catch (_) {
      // Platforms that don't report it (older OS versions, desktop, web) have
      // no reduced mode to report. Treating the silence as precise matches
      // what those platforms actually do.
      return LocationAccess.granted;
    }

    if (status == LocationAccuracyStatus.precise) return LocationAccess.granted;

    if (defaultTargetPlatform == TargetPlatform.iOS &&
        !_askedForTemporaryAccuracy) {
      _askedForTemporaryAccuracy = true;
      try {
        // The purpose key must match the entry under
        // NSLocationTemporaryUsageDescriptionDictionary in Info.plist exactly,
        // or iOS silently refuses to show the prompt.
        final upgraded = await Geolocator.requestTemporaryFullAccuracy(
          purposeKey: 'PreciseWalkTracking',
        );
        if (upgraded == LocationAccuracyStatus.precise) {
          return LocationAccess.granted;
        }
      } catch (error) {
        AppLogger.warn(_tag, 'temporary full accuracy request failed', error);
      }
    }

    AppLogger.info(_tag, 'reduced accuracy granted — traces will be rough');
    return LocationAccess.grantedApproximate;
  }

  /// One look at the device: the access we have, and the fix it produced.
  ///
  /// Both come back from a single call so the caller pays for one permission
  /// prompt and can still tell "you refused" apart from "still looking".
  Future<LocationReading> read() async {
    final access = await ensureAccess();
    if (!access.canRecord) return LocationReading(access: access);
    return LocationReading(access: access, fix: await currentFix());
  }

  /// One fix, for centring the record screen's map. Assumes access has already
  /// been established — [read] is the entry point that checks.
  ///
  /// Returns null rather than throwing when the position simply isn't
  /// available yet — and, importantly, when the only thing available is a
  /// cached position too old or too coarse to stand behind. The previous
  /// version of this method returned `getLastKnownPosition()` unconditionally,
  /// which is how a fix from yesterday's other city gets drawn as "you are
  /// here" with nothing on screen to say otherwise.
  Future<LocationFix?> currentFix() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: _oneShotSettings(),
      );
      final fix = _fixFrom(position);
      _log('fix', fix);
      return fix;
    } catch (error) {
      AppLogger.debug(_tag, 'one-shot fix failed ($error) — trying cache');
    }

    final last = await Geolocator.getLastKnownPosition();
    if (last == null) return null;

    final cached = _fixFrom(last);
    if (!cached.isDisplayable) {
      AppLogger.debug(
        _tag,
        'cached fix rejected: ${cached.describe()}',
      );
      return null;
    }
    _log('cached fix', cached);
    return cached;
  }

  /// The recording stream.
  ///
  /// `distanceFilter: 5` means the platform only wakes us once the device has
  /// actually moved five metres, which is the first and cheapest layer of
  /// noise rejection. `bestForNavigation` asks for the GNSS chip rather than
  /// whatever the fused provider considers good enough, which is what stops a
  /// walk opening on a cell-tower fix.
  Stream<LocationFix> positionStream() {
    return Geolocator.getPositionStream(locationSettings: _streamSettings())
        .map(_fixFrom);
  }

  Future<void> openAppSettings() => Geolocator.openAppSettings();

  Future<void> openLocationSettings() => Geolocator.openLocationSettings();

  // ------------------------------------------------------ platform settings ---

  LocationSettings _oneShotSettings() {
    const accuracy = LocationAccuracy.best;
    const timeLimit = LocationQuality.oneShotTimeout;

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidSettings(
        accuracy: accuracy,
        timeLimit: timeLimit,
        // The Fused Location Provider is materially more accurate than the raw
        // LocationManager. Never force the legacy path.
        forceLocationManager: false,
      ),
      TargetPlatform.iOS || TargetPlatform.macOS => AppleSettings(
        accuracy: accuracy,
        timeLimit: timeLimit,
      ),
      _ => const LocationSettings(accuracy: accuracy, timeLimit: timeLimit),
    };
  }

  LocationSettings _streamSettings() {
    const accuracy = LocationAccuracy.bestForNavigation;
    const distanceFilter = 5;

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        intervalDuration: const Duration(seconds: 1),
        forceLocationManager: false,
      ),
      TargetPlatform.iOS || TargetPlatform.macOS => AppleSettings(
        accuracy: accuracy,
        activityType: ActivityType.fitness,
        distanceFilter: distanceFilter,
        // Letting iOS pause updates mid-walk leaves a gap in the trace that
        // looks like a teleport when it resumes.
        pauseLocationUpdatesAutomatically: false,
      ),
      _ => const LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
      ),
    };
  }

  void _log(String what, LocationFix fix) =>
      AppLogger.debug(_tag, '$what ${fix.describe()}');
}

/// The one place a `geolocator` [Position] becomes an app [LocationFix].
///
/// A free function rather than a factory on [LocationFix] itself, so the domain
/// type stays free of the plugin and the repository interface can return it.
LocationFix _fixFrom(Position position) => LocationFix(
  point: LatLng(position.latitude, position.longitude),
  accuracyMeters: position.accuracy,
  altitudeMeters: position.altitude,
  timestamp: position.timestamp,
);

/// Straight-line distance between two points, in metres.
///
/// Sits here so the recorder doesn't have to import `geolocator` for the one
/// piece of maths it needs.
double distanceBetweenMeters(LatLng a, LatLng b) =>
    Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude);

final locationServiceProvider = Provider<LocationService>(
  (ref) => LocationService(),
);
