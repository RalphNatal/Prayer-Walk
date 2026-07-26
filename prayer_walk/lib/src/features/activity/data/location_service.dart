import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Why the app can't read the device's position, in the four shapes the UI
/// actually has to act on differently.
enum LocationAccess {
  /// Good to record.
  granted,

  /// Denied this time. Asking again is allowed — the button can retry.
  denied,

  /// Denied permanently (or restricted). Only Settings can undo it.
  deniedForever,

  /// Location is switched off device-wide. Not a permission problem.
  serviceDisabled,
}

/// The single file that imports `geolocator`.
///
/// Everything above it speaks in [LatLng], [LocationAccess] and a stream of
/// [LocationFix]. Swapping the plugin means rewriting this file and nothing
/// else — the same bargain [RouteMapView] makes with `flutter_map`.
///
/// Foreground only this phase: no background service, no `Always` permission.
class LocationService {
  const LocationService();

  /// Checks the service and the permission, asking for the latter if it has
  /// not been decided yet. Safe to call repeatedly — a granted permission
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
      LocationPermission.always ||
      LocationPermission.whileInUse => LocationAccess.granted,
      LocationPermission.deniedForever => LocationAccess.deniedForever,
      // `unableToDetermine` is treated as a soft denial: retryable, since it
      // usually means the platform hasn't answered yet rather than "no".
      LocationPermission.denied ||
      LocationPermission.unableToDetermine => LocationAccess.denied,
    };
  }

  /// One fix, for centring the record screen's map. Returns null rather than
  /// throwing when the position simply isn't available yet.
  Future<LatLng?> currentFix() async {
    if (await ensureAccess() != LocationAccess.granted) return null;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return LatLng(position.latitude, position.longitude);
    } catch (_) {
      // Timed out, or the platform refused. The caller falls back to a
      // last-known fix or the default centre.
      final last = await Geolocator.getLastKnownPosition();
      return last == null ? null : LatLng(last.latitude, last.longitude);
    }
  }

  /// The recording stream. `distanceFilter: 5` means the platform only wakes us
  /// once the device has actually moved five metres, which is the first and
  /// cheapest layer of noise rejection.
  Stream<LocationFix> positionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).map(LocationFix.fromPosition);
  }

  Future<void> openAppSettings() => Geolocator.openAppSettings();

  Future<void> openLocationSettings() => Geolocator.openLocationSettings();
}

/// One position reading, reduced to what the recorder needs.
class LocationFix {
  const LocationFix({
    required this.point,
    required this.accuracyMeters,
    required this.altitudeMeters,
    required this.timestamp,
  });

  factory LocationFix.fromPosition(Position position) => LocationFix(
    point: LatLng(position.latitude, position.longitude),
    accuracyMeters: position.accuracy,
    altitudeMeters: position.altitude,
    timestamp: position.timestamp,
  );

  final LatLng point;

  /// Radius of 68% confidence, in metres. Bigger is worse.
  final double accuracyMeters;

  /// Metres above the WGS-84 ellipsoid. Notoriously noisy on phones — treat
  /// anything derived from it as approximate.
  final double altitudeMeters;

  final DateTime timestamp;
}

/// Straight-line distance between two points, in metres.
///
/// Sits here so the recorder doesn't have to import `geolocator` for the one
/// piece of maths it needs.
double distanceBetweenMeters(LatLng a, LatLng b) =>
    Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude);

final locationServiceProvider = Provider<LocationService>(
  (ref) => const LocationService(),
);
