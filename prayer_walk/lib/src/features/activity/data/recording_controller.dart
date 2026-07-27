import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/utils/app_logger.dart';
import '../../auth/data/auth_providers.dart';
import '../domain/activity.dart';
import 'geocoding_service.dart';
import 'location_service.dart';
import 'activity_providers.dart';

/// Where the recorder is in its lifecycle.
enum RecordingStatus {
  /// Nothing started. The record screen's resting state.
  idle,

  /// Waiting on the OS permission prompt or the first fix.
  requesting,

  /// Consuming positions.
  recording,

  /// Subscribed but ignoring positions; the clock is stopped.
  paused,

  /// Stopped, with a draft ready for the summary screen.
  finished,
}

/// State carried across the record -> live -> summary flow.
class RecordingState {
  const RecordingState({
    this.type = ActivityType.walk,
    this.intentions = const [],
    this.draft,
    this.status = RecordingStatus.idle,
    this.devotionalTitle,
    this.startedAt,
    this.elapsed = Duration.zero,
    this.distanceMeters = 0,
    this.elevationGainMeters = 0,
    this.route = const [],
    this.waypoints = const [],
    this.access,
    this.accuracyMeters,
    this.warmingUp = false,
  });

  final ActivityType type;

  /// Intentions chosen before starting, carried onto the saved activity.
  final List<PrayerIntention> intentions;

  /// Set when the walk was started from a devotional. Shown through the flow
  /// as context; it is not stored on the saved activity — devotional-to-
  /// activity linkage is not modelled yet.
  final String? devotionalTitle;

  /// Assembled by [RecordingController.finish]; the summary edits it in place.
  final ActivityDraft? draft;

  final RecordingStatus status;

  // ------------------------------------------------------------ live data ---

  final DateTime? startedAt;

  /// Moving time — paused seconds are never added.
  final Duration elapsed;

  final double distanceMeters;
  final double elevationGainMeters;

  /// The route as recorded so far. Grows with every accepted fix.
  final List<LatLng> route;
  final List<Waypoint> waypoints;

  /// Why the last [RecordingController.start] failed, when it did — or
  /// [LocationAccess.grantedApproximate] when it succeeded on reduced accuracy,
  /// which the live screen has to keep saying out loud. Null while things are
  /// fine.
  final LocationAccess? access;

  /// The accuracy radius of the most recent fix the device delivered, accepted
  /// or not. Drives the signal indicator; null before the first fix arrives.
  final double? accuracyMeters;

  /// True while the recorder is deliberately holding fixes back, waiting for
  /// the signal to sharpen before it anchors the route.
  final bool warmingUp;

  /// How the current signal should be described. Reads the same scale the
  /// one-shot fix does, so "sharp" means the same thing on both screens.
  LocationSignal get signal {
    final accuracy = accuracyMeters;
    if (accuracy == null || accuracy <= 0) return LocationSignal.unknown;
    if (accuracy <= LocationQuality.goodAccuracyMeters) {
      return LocationSignal.sharp;
    }
    if (accuracy <= LocationQuality.maxDisplayAccuracyMeters) {
      return LocationSignal.fair;
    }
    return LocationSignal.weak;
  }

  /// Recording on approximate permission — the trace will be rough and the UI
  /// must say so rather than presenting a kilometre-wide error as a walk.
  bool get isApproximate => access == LocationAccess.grantedApproximate;

  bool get hasDraft => draft != null;

  bool get isPaused => status == RecordingStatus.paused;

  bool get isLive =>
      status == RecordingStatus.recording || status == RecordingStatus.paused;

  /// The newest point, for the map's "you are here".
  LatLng? get lastPoint => route.isEmpty ? null : route.last;

  RecordingState copyWith({
    ActivityType? type,
    List<PrayerIntention>? intentions,
    ActivityDraft? draft,
    RecordingStatus? status,
    String? devotionalTitle,
    DateTime? startedAt,
    Duration? elapsed,
    double? distanceMeters,
    double? elevationGainMeters,
    List<LatLng>? route,
    List<Waypoint>? waypoints,
    LocationAccess? access,
    double? accuracyMeters,
    bool? warmingUp,
    bool clearDraft = false,
    bool clearDevotional = false,
    bool clearAccess = false,
    bool clearAccuracy = false,
  }) {
    return RecordingState(
      type: type ?? this.type,
      intentions: intentions ?? this.intentions,
      draft: clearDraft ? null : (draft ?? this.draft),
      status: status ?? this.status,
      devotionalTitle: clearDevotional
          ? null
          : (devotionalTitle ?? this.devotionalTitle),
      startedAt: startedAt ?? this.startedAt,
      elapsed: elapsed ?? this.elapsed,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      elevationGainMeters: elevationGainMeters ?? this.elevationGainMeters,
      route: route ?? this.route,
      waypoints: waypoints ?? this.waypoints,
      access: clearAccess ? null : (access ?? this.access),
      accuracyMeters: clearAccuracy
          ? null
          : (accuracyMeters ?? this.accuracyMeters),
      warmingUp: warmingUp ?? this.warmingUp,
    );
  }
}

/// Drives a real recording: permissions, the position stream, the clock, and
/// the running totals.
///
/// Foreground only. The stream is a plain `getPositionStream` subscription, so
/// it stops when the OS stops delivering to a backgrounded app — background
/// tracking is a separate phase with its own service and permission.
///
/// Three invariants the tests of "believable stats" rest on:
///  * a fix is only *accepted* if it is accurate enough and far enough from the
///    last accepted one, so standing still doesn't accumulate metres;
///  * `_previous` is cleared on pause, so resuming never draws — or measures —
///    the straight line across wherever the walker went while paused;
///  * nothing is plotted until the signal reaches recording grade (or the
///    warm-up window expires), so the route is never anchored on the coarse
///    network fix a cold GPS start hands over first.
class RecordingController extends Notifier<RecordingState> {
  StreamSubscription<LocationFix>? _subscription;
  Timer? _ticker;

  /// The last *accepted* fix. Null before the first one and immediately after
  /// a resume, which is what breaks the segment across a pause.
  LocationFix? _previous;

  /// Altitude of the last accepted fix, for the elevation delta.
  double? _previousAltitude;

  /// When the warm-up gate opened. Null once the gate has closed for good.
  DateTime? _warmUpStartedAt;

  static const _tag = 'PW-REC';

  // The thresholds live in [LocationQuality] rather than here, so the recorder
  // and the location service cannot drift into disagreeing about how accurate
  // a fix has to be.

  @override
  RecordingState build() {
    // A Notifier can be disposed while a walk is in flight (the provider is
    // refreshed, the container is torn down). Without this the subscription
    // and ticker outlive it and keep waking the GPS.
    ref.onDispose(_stopStreams);
    return const RecordingState();
  }

  // ----------------------------------------------------------- pre-flight ---

  void selectType(ActivityType type) {
    state = state.copyWith(type: type);
  }

  /// Called from the devotional reader's "Start a walk with this".
  void carryDevotional(String title) =>
      state = state.copyWith(devotionalTitle: title);

  void dropDevotional() => state = state.copyWith(clearDevotional: true);

  void toggleIntention(PrayerIntention intention) {
    final existing = state.intentions.any((i) => i.id == intention.id);
    state = state.copyWith(
      intentions: existing
          ? state.intentions.where((i) => i.id != intention.id).toList()
          : [...state.intentions, intention],
    );
  }

  void addIntention(String text, PrayerCategory category) {
    if (text.trim().isEmpty) return;
    state = state.copyWith(
      intentions: [
        ...state.intentions,
        PrayerIntention(
          id: 'i_local_${DateTime.now().microsecondsSinceEpoch}',
          text: text.trim(),
          category: category,
          createdAt: DateTime.now(),
        ),
      ],
    );
  }

  void removeIntention(String id) {
    state = state.copyWith(
      intentions: state.intentions.where((i) => i.id != id).toList(),
    );
  }

  // ------------------------------------------------------------ recording ---

  /// Runs the permission gate and, on success, opens the position stream.
  ///
  /// Returns the access result so the screen can decide what to show; it never
  /// throws for a denial, since a denial is an ordinary answer. An *approximate*
  /// grant is a success — recording proceeds — but it is carried into the state
  /// so the live screen can keep saying the trace will be rough.
  Future<LocationAccess> start() async {
    if (state.isLive) return state.access ?? LocationAccess.granted;

    state = state.copyWith(
      status: RecordingStatus.requesting,
      clearAccess: true,
    );

    final access = await ref.read(locationServiceProvider).ensureAccess();
    if (!access.canRecord) {
      state = state.copyWith(status: RecordingStatus.idle, access: access);
      return access;
    }

    _previous = null;
    _previousAltitude = null;
    // The gate that kills the classic opening jump: a cold GPS start emits a
    // coarse network fix first, and anchoring the route on it puts the first
    // point hundreds of metres from where the walk actually began.
    _warmUpStartedAt = DateTime.now();
    state = state.copyWith(
      status: RecordingStatus.recording,
      startedAt: DateTime.now(),
      elapsed: Duration.zero,
      distanceMeters: 0,
      elevationGainMeters: 0,
      route: const [],
      waypoints: const [],
      warmingUp: true,
      clearDraft: true,
      clearAccuracy: true,
      // Precise clears the notice; approximate keeps it on screen.
      clearAccess: access.isPrecise,
      access: access.isPrecise ? null : access,
    );

    _subscription = ref
        .read(locationServiceProvider)
        .positionStream()
        .listen(_onFix, onError: (_) {/* A dropped fix is not fatal. */});

    _ticker = Timer.periodic(const Duration(seconds: 1), _onTick);
    return access;
  }

  void _onTick(Timer _) {
    if (state.status != RecordingStatus.recording) return;
    state = state.copyWith(elapsed: state.elapsed + const Duration(seconds: 1));
  }

  /// Accumulates one position into the running totals — the whole of the
  /// "believable stats" policy lives here.
  void _onFix(LocationFix fix) {
    // Paused: stay subscribed (re-acquiring a lock is slow and battery-hungry)
    // but consume nothing beyond the signal reading, which the indicator still
    // wants to be honest about.
    if (state.status != RecordingStatus.recording) {
      state = state.copyWith(accuracyMeters: fix.accuracyMeters);
      return;
    }

    // A wide accuracy radius means the position could be anywhere in it.
    if (fix.accuracyMeters > LocationQuality.maxRecordingAccuracyMeters) {
      state = state.copyWith(accuracyMeters: fix.accuracyMeters);
      return;
    }

    if (_isWarmingUp(fix)) {
      state = state.copyWith(accuracyMeters: fix.accuracyMeters);
      return;
    }

    if (kDebugMode) {
      AppLogger.debug(_tag, 'accepted ${fix.describe()}');
    }

    final previous = _previous;
    if (previous == null) {
      // First fix of the walk, or the first after a resume: it starts a new
      // segment and contributes no distance.
      _previous = fix;
      _previousAltitude = fix.altitudeMeters;
      state = state.copyWith(route: [...state.route, fix.point]);
      return;
    }

    final step = distanceBetweenMeters(previous.point, fix.point);
    if (step < LocationQuality.minStepMeters) {
      state = state.copyWith(accuracyMeters: fix.accuracyMeters);
      return;
    }

    final climb = fix.altitudeMeters - (_previousAltitude ?? fix.altitudeMeters);

    _previous = fix;
    _previousAltitude = fix.altitudeMeters;
    state = state.copyWith(
      route: [...state.route, fix.point],
      distanceMeters: state.distanceMeters + step,
      accuracyMeters: fix.accuracyMeters,
      elevationGainMeters: climb > LocationQuality.minClimbMeters
          ? state.elevationGainMeters + climb
          : state.elevationGainMeters,
    );
  }

  /// The warm-up gate: hold fixes back until the signal reaches recording
  /// grade, or until the window runs out.
  ///
  /// Returns true while the fix should be dropped. Once the gate closes it
  /// stays closed for the rest of the walk — a pause mid-route already keeps
  /// its own lock, and re-gating there would swallow the first fix after every
  /// resume.
  bool _isWarmingUp(LocationFix fix) {
    final startedAt = _warmUpStartedAt;
    if (startedAt == null) return false;

    final sharp =
        fix.hasAccuracy &&
        fix.accuracyMeters <= LocationQuality.goodAccuracyMeters;
    final expired =
        DateTime.now().difference(startedAt) >= LocationQuality.warmUpWindow;

    if (!sharp && !expired) return true;

    _warmUpStartedAt = null;
    state = state.copyWith(warmingUp: false);
    if (kDebugMode) {
      AppLogger.debug(
        _tag,
        expired && !sharp
            ? 'warm-up timed out at ±${fix.accuracyMeters.round()}m — '
                  'starting anyway'
            : 'warm-up done at ±${fix.accuracyMeters.round()}m',
      );
    }
    return false;
  }

  void togglePause() => state.isPaused ? resume() : pause();

  void pause() {
    if (state.status != RecordingStatus.recording) return;
    // Dropping the previous fix is what stops the resume from measuring the
    // straight line across the gap.
    _previous = null;
    state = state.copyWith(status: RecordingStatus.paused);
  }

  void resume() {
    if (state.status != RecordingStatus.paused) return;
    _previous = null;
    state = state.copyWith(status: RecordingStatus.recording);
  }

  /// Tags the current position with a prayer waypoint.
  void dropWaypoint(WaypointKind kind, {String label = '', String note = ''}) {
    final point = state.lastPoint;
    if (point == null || !state.isLive) return;
    state = state.copyWith(
      waypoints: [
        ...state.waypoints,
        Waypoint(
          id: 'w_local_${DateTime.now().microsecondsSinceEpoch}',
          point: point,
          kind: kind,
          label: label.trim().isEmpty ? kind.label : label.trim(),
          note: note.trim(),
          elapsed: state.elapsed,
        ),
      ],
    );
  }

  /// Stops recording and assembles the draft the summary screen edits.
  void finish() {
    if (!state.isLive) return;
    _stopStreams();
    final startedAt = state.startedAt ?? DateTime.now();
    state = state.copyWith(
      status: RecordingStatus.finished,
      warmingUp: false,
      draft: ActivityDraft(
        type: state.type,
        title: defaultTitle(state.type, startedAt),
        startedAt: startedAt,
        duration: state.elapsed,
        distanceMeters: state.distanceMeters,
        elevationGainMeters: state.elevationGainMeters,
        route: List.unmodifiable(state.route),
        waypoints: List.unmodifiable(state.waypoints),
        intentions: state.intentions,
      ),
    );

    // Fire-and-forget: the summary screen is already usable, and a walk must
    // never wait on a geocoding endpoint to be saveable.
    unawaited(_resolvePlaceName());
  }

  /// Names the walk by where it happened — "Morning walk in Antipolo".
  ///
  /// Deliberately after [finish] rather than inside it: the lookup is remote
  /// and the summary screen must appear immediately. If it lands, the title
  /// upgrades under the walker; if it doesn't, they keep a perfectly good
  /// plain title and never learn a request was made.
  Future<void> _resolvePlaceName() async {
    final draft = state.draft;
    if (draft == null || draft.route.isEmpty) return;

    final place = await ref
        .read(geocodingServiceProvider)
        .reverseGeocode(draft.route.first);
    if (place == null) return;

    final current = state.draft;
    // The walker may have retitled, discarded or saved while we were away.
    // Only an untouched default title gets rewritten — never their words.
    if (current == null || current.title != draft.title) return;

    state = state.copyWith(
      draft: current.copyWith(
        title: '${current.title} in $place',
        placeName: place,
      ),
    );
  }

  // -------------------------------------------------------------- summary ---

  void editDraft({String? title, String? note}) {
    final draft = state.draft;
    if (draft == null) return;
    state = state.copyWith(draft: draft.copyWith(title: title, note: note));
  }

  void setDraftIntentions(List<PrayerIntention> intentions) {
    final draft = state.draft;
    state = state.copyWith(
      intentions: intentions,
      draft: draft?.copyWith(intentions: intentions),
    );
  }

  /// Commits the draft and clears the flow. Returns the stored activity id.
  Future<String> save() async {
    final draft = state.draft;
    final userId = ref.read(currentAuthUserIdProvider);
    if (draft == null || userId == null) {
      throw StateError('save() called with nothing recorded');
    }
    final titled = draft.title.trim().isEmpty
        ? draft.copyWith(title: defaultTitle(draft.type, draft.startedAt))
        : draft;
    final saved = await ref
        .read(activityRepositoryProvider)
        .saveDraft(userId, titled);
    reset();
    return saved.id;
  }

  /// Throws the recording away without writing anything.
  void discard() => reset();

  void reset() {
    _stopStreams();
    state = const RecordingState();
  }

  void _stopStreams() {
    _subscription?.cancel();
    _subscription = null;
    _ticker?.cancel();
    _ticker = null;
    _previous = null;
    _previousAltitude = null;
    _warmUpStartedAt = null;
  }

  static String defaultTitle(ActivityType type, DateTime at) {
    final hour = at.hour;
    final partOfDay = hour < 11
        ? 'Morning'
        : hour < 15
        ? 'Midday'
        : hour < 19
        ? 'Afternoon'
        : 'Evening';
    return '$partOfDay ${type.label.toLowerCase()}';
  }
}

final recordingControllerProvider =
    NotifierProvider<RecordingController, RecordingState>(
      RecordingController.new,
    );
