import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `AndroidSettings`, `AppleSettings` and `ActivityType` come through this one
// import — geolocator 14 re-exports the platform packages, so the settings
// types are available without depending on `geolocator_android` /
// `geolocator_apple` directly.
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../../../core/theme/app_colors.dart';
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
/// ## Recording in a pocket
///
/// A walk has to survive the screen locking, another app coming to the front,
/// and the phone going into a pocket for an hour. Two different mechanisms do
/// that, and both are configured here:
///
///  * **Android** — [positionStream] with `background: true` hands geolocator a
///    [ForegroundNotificationConfig], which makes it run its location work in a
///    foreground service with a persistent notification. A service typed
///    `location`, started while the app is on screen, may read position for as
///    long as it lives on nothing more than the ordinary when-in-use grant.
///  * **iOS** — `allowBackgroundLocationUpdates`, paired with the `location`
///    entry in `UIBackgroundModes`. When-in-use is enough there too; what the
///    flag buys is that iOS keeps delivering after the app leaves the screen,
///    and the blue indicator says so for as long as it is set.
///
/// Both are switched on by the `background` flag and by nothing else, so the
/// service, the wake lock and the blue indicator exist for exactly the span of
/// a recording. That is a battery promise and a store-review promise at once.
///
/// ## Why `permission_handler` is in this file
///
/// It is here for one reason, and it is not a style choice.
/// `Geolocator.requestPermission()` on Android appends
/// `ACCESS_BACKGROUND_LOCATION` to the *same* `requestPermissions` call as
/// fine/coarse whenever the manifest declares it (see
/// `PermissionManager.requestPermission` in geolocator_android). Android 11 and
/// above silently deny a request that mixes foreground and background location:
/// no dialog is shown, nothing is granted, and the walker sees a Start button
/// that does nothing. So the two are asked for separately, through the one
/// plugin that will ask for them separately. geolocator stays the only thing
/// that *reads* position; permission_handler only ever asks questions.
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
      permission = await _requestForegroundPermission();
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

  /// Asks for **when-in-use only**, whatever the manifest happens to declare.
  ///
  /// On Android this cannot go through `Geolocator.requestPermission()` any
  /// more: with `ACCESS_BACKGROUND_LOCATION` in the manifest, geolocator adds it
  /// to the same request as fine/coarse, and Android 11+ answers a mixed
  /// foreground/background request by showing nothing and granting nothing.
  /// The walk would fail at the first press of Start, with no dialog to explain
  /// it. `permission_handler` asks for fine and coarse alone, which is the
  /// request the platform will actually put on screen.
  ///
  /// The answer is translated back into geolocator's vocabulary so the rest of
  /// this class is unchanged — including the `deniedForever` case, which
  /// `Geolocator.checkPermission()` cannot report on Android (it has no way to
  /// tell a fresh refusal from a permanent one) but `permission_handler` can.
  Future<LocationPermission> _requestForegroundPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Geolocator.requestPermission();
    }

    final ph.PermissionStatus status;
    try {
      status = await ph.Permission.locationWhenInUse.request();
    } catch (error) {
      // No plugin (a test, a desktop build) or a platform that refused the
      // call. Geolocator's own request is the honest fallback: on any platform
      // that reaches this line, it is not the one with the bundling problem.
      AppLogger.info(
        _tag,
        'staged permission request unavailable (${error.runtimeType})',
      );
      return Geolocator.requestPermission();
    }

    if (status.isGranted || status.isLimited) {
      // Ask geolocator rather than assuming: it is the one that knows whether
      // what landed was `whileInUse` or `always`, and the difference matters to
      // nothing here but costs nothing to keep accurate.
      return Geolocator.checkPermission();
    }
    if (status.isPermanentlyDenied) return LocationPermission.deniedForever;
    return LocationPermission.denied;
  }

  // ------------------------------------------------- recording in a pocket ---

  /// What background access the app currently holds, without asking anybody.
  ///
  /// Safe to call whenever — it shows no dialog. Used to decide whether the
  /// walker has anything left to be offered.
  Future<BackgroundLocationAccess> backgroundAccess() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return BackgroundLocationAccess.notApplicable;
    }
    try {
      final status = await ph.Permission.locationAlways.status;
      if (status.isGranted) return BackgroundLocationAccess.granted;
      if (status.isPermanentlyDenied) {
        return BackgroundLocationAccess.deniedForever;
      }
      return BackgroundLocationAccess.denied;
    } catch (error) {
      AppLogger.info(
        _tag,
        'background access unreadable (${error.runtimeType})',
      );
      return BackgroundLocationAccess.notApplicable;
    }
  }

  /// The **second** permission step, and it must stay second.
  ///
  /// Android rejects a background-location request that arrives before, or
  /// bundled with, the foreground one — so this refuses to ask until
  /// when-in-use is actually held, rather than firing a request the platform
  /// will drop on the floor. The caller's job is the other half of the rule:
  /// this is only ever reached from the start of a recording, never from
  /// launch, and the answer is remembered so nobody is asked twice.
  ///
  /// A refusal is an ordinary answer. On Android 11 and above it is the
  /// *expected* answer: the platform stopped showing a dialog for background
  /// location and moved the choice to a settings page, so `request()` there
  /// comes straight back as [BackgroundLocationAccess.deniedForever] and the
  /// only useful next move is to offer that page. Nothing about the walk
  /// changes either way — the foreground service is what carries it.
  Future<BackgroundLocationAccess> requestBackgroundAccess() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return BackgroundLocationAccess.notApplicable;
    }

    final foreground = await Geolocator.checkPermission();
    if (foreground != LocationPermission.whileInUse &&
        foreground != LocationPermission.always) {
      AppLogger.info(_tag, 'background asked for before when-in-use — skipped');
      return BackgroundLocationAccess.denied;
    }

    try {
      final status = await ph.Permission.locationAlways.request();
      if (status.isGranted) return BackgroundLocationAccess.granted;
      if (status.isPermanentlyDenied) {
        return BackgroundLocationAccess.deniedForever;
      }
      return BackgroundLocationAccess.denied;
    } catch (error) {
      AppLogger.info(
        _tag,
        'background request unavailable (${error.runtimeType})',
      );
      return BackgroundLocationAccess.notApplicable;
    }
  }

  /// Android 13+ will not *show* the foreground-service notification without
  /// `POST_NOTIFICATIONS`.
  ///
  /// The service still runs and the walk still records — but a walk being
  /// recorded with nothing on screen to say so is precisely what the ongoing
  /// notification exists to prevent, so this is asked at the start of a
  /// recording alongside the location prompt. Returns whether the notification
  /// will be visible; never blocks anything.
  Future<bool> ensureNotificationAccess() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      final status = await ph.Permission.notification.request();
      if (!status.isGranted) {
        AppLogger.info(_tag, 'recording notification will be hidden ($status)');
      }
      return status.isGranted;
    } catch (error) {
      AppLogger.info(
        _tag,
        'notification permission unavailable (${error.runtimeType})',
      );
      return false;
    }
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
  ///
  /// [background] is what makes the walk survive a pocket: the Android
  /// foreground service and the iOS background-location flag are both switched
  /// on by it and by nothing else. **Pass false unless a recording is actually
  /// running.** Cancelling the subscription is what takes the service, the wake
  /// lock and the blue indicator away again, which is why the recorder cancels
  /// the instant a walk ends.
  Stream<LocationFix> positionStream({bool background = false}) {
    return Geolocator.getPositionStream(
      locationSettings: _streamSettings(background: background),
    ).map(_fixFrom);
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
        // Explicitly off, because `AppleSettings` defaults it *on*. Centring
        // the record screen's map is not a recording, and now that the
        // `location` background mode is in Info.plist the default would put the
        // blue indicator on screen for it.
        allowBackgroundLocationUpdates: false,
        showBackgroundLocationIndicator: false,
      ),
      _ => const LocationSettings(accuracy: accuracy, timeLimit: timeLimit),
    };
  }

  LocationSettings _streamSettings({required bool background}) {
    const accuracy = LocationAccuracy.bestForNavigation;
    // Five metres and one second. Deliberately unchanged from the foreground-
    // only version: sampling harder to compensate for background behaviour
    // would buy nothing but battery, and the noise filters upstream are tuned
    // against exactly these numbers.
    const distanceFilter = 5;

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        intervalDuration: const Duration(seconds: 1),
        // The Fused Location Provider is materially more accurate than the raw
        // LocationManager. Never force the legacy path.
        forceLocationManager: false,
        // Non-null is the whole switch: geolocator runs its location work in a
        // foreground service when a notification config is present, and in the
        // activity's own process when it is not.
        foregroundNotificationConfig: background
            ? _recordingNotification
            : null,
      ),
      TargetPlatform.iOS || TargetPlatform.macOS => AppleSettings(
        accuracy: accuracy,
        activityType: ActivityType.fitness,
        distanceFilter: distanceFilter,
        // Letting iOS pause updates mid-walk leaves a gap in the trace that
        // looks like a teleport when it resumes — and a walk that is never
        // un-paused, which is the more common and worse failure.
        pauseLocationUpdatesAutomatically: false,
        // Explicit on both branches. The plugin's default for this is `true`,
        // which would leave the blue background indicator on for a map that is
        // only being centred.
        allowBackgroundLocationUpdates: background,
        showBackgroundLocationIndicator: background,
      ),
      _ => const LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
      ),
    };
  }

  /// The ongoing notification that stands for a running recording.
  ///
  /// The text cannot be live. geolocator takes this configuration once, when
  /// the stream is listened to, and exposes no way to rewrite it afterwards —
  /// the only route to a changing distance would be to tear the stream down and
  /// open a new one every few seconds, which would cost the GNSS lock each
  /// time. So it says the true, unchanging thing instead of a stale number.
  ///
  /// Tapping it returns to the walk: geolocator attaches the launcher intent
  /// with `RESET_TASK_IF_NEEDED`, which brings the existing task forward with
  /// the live screen still on top of it rather than starting the app again.
  static const _recordingNotification = ForegroundNotificationConfig(
    notificationTitle: 'Prayer Walk',
    notificationText: 'Recording your walk. Tap to open it.',
    // What the walker sees if they go looking for this in system settings, so
    // it names the walk rather than the plugin's default "Background Location".
    notificationChannelName: 'Walk recording',
    notificationIcon: AndroidResource(
      name: 'ic_stat_recording',
      defType: 'drawable',
    ),
    // Held for the life of the recording and released with it. Without it Doze
    // batches fixes and delivers them in a clump minutes later, which is a
    // stalled distance on screen and a route drawn in long straight jumps.
    enableWakeLock: true,
    // A recording is not something to be swiped away by accident. Finish is on
    // the live screen, one tap from here.
    setOngoing: true,
    color: AppColors.pine,
  );

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
