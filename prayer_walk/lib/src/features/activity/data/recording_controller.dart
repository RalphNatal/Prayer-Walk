import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/config/app_config.dart';
import '../../../core/utils/app_logger.dart';
import '../../auth/data/auth_providers.dart';
import '../../devotionals/domain/devotional.dart' show DevotionalCategory;
import '../../privacy/domain/activity_visibility.dart';
import '../../scripture/data/scripture_history_controller.dart';
import '../../scripture/data/scripture_providers.dart';
import '../../scripture/domain/scripture_prompt.dart';
import '../../scripture/domain/scripture_selector.dart';
import '../../scripture/domain/scripture_settings.dart';
import '../domain/activity.dart';
import '../domain/cadence_trigger.dart';
import '../domain/interrupted_recording.dart';
import 'geocoding_service.dart';
import 'location_service.dart';
import 'activity_providers.dart';
import 'recording_journal.dart';
import 'step_cadence_trigger.dart';

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
    this.devotionalCategory,
    this.scripture = const ScriptureSettings(),
    this.scriptureFellBackToDistance = false,
    this.deliveredPrompts = const [],
    this.currentPrompt,
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

  /// The theme of that devotional, when the walk was started from one. Used
  /// only to bias which verses arrive — a scripture walk started from a
  /// Lament devotional should not open with a psalm of thanksgiving.
  final DevotionalCategory? devotionalCategory;

  // ----------------------------------------------- scripture on the trail ---

  /// The scripture settings *this walk* is running under.
  ///
  /// Snapshotted from the stored preference when the walk starts, so the live
  /// mute control changes this walk without rewriting what the walker has
  /// chosen as their default. Everything before the walk edits the preference;
  /// everything during it edits this.
  final ScriptureSettings scripture;

  /// True when step cadence was asked for and the device could not supply it,
  /// so the walk is running on distance instead. The live screen says this
  /// once and then leaves it alone.
  final bool scriptureFellBackToDistance;

  /// Everything that has arrived on this walk, oldest first. Kept so a verse
  /// missed while the phone was in a pocket is still there to be read.
  final List<DeliveredPrompt> deliveredPrompts;

  /// The one currently on screen, or null once it has been let go. A fresh
  /// instance per arrival, which is what the live screen keys its chime off.
  final DeliveredPrompt? currentPrompt;

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

  /// Whether this walk is running with both audio channels off. The live
  /// screen's mute control reads and writes exactly this.
  bool get scriptureMuted => !scripture.sound && !scripture.voice;

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
    DevotionalCategory? devotionalCategory,
    ScriptureSettings? scripture,
    bool? scriptureFellBackToDistance,
    List<DeliveredPrompt>? deliveredPrompts,
    DeliveredPrompt? currentPrompt,
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
    bool clearCurrentPrompt = false,
  }) {
    return RecordingState(
      type: type ?? this.type,
      intentions: intentions ?? this.intentions,
      draft: clearDraft ? null : (draft ?? this.draft),
      status: status ?? this.status,
      devotionalTitle: clearDevotional
          ? null
          : (devotionalTitle ?? this.devotionalTitle),
      devotionalCategory: clearDevotional
          ? null
          : (devotionalCategory ?? this.devotionalCategory),
      scripture: scripture ?? this.scripture,
      scriptureFellBackToDistance:
          scriptureFellBackToDistance ?? this.scriptureFellBackToDistance,
      deliveredPrompts: deliveredPrompts ?? this.deliveredPrompts,
      currentPrompt: clearCurrentPrompt
          ? null
          : (currentPrompt ?? this.currentPrompt),
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
/// Three invariants the tests of "believable stats" rest on:
///  * a fix is only *accepted* if it is accurate enough and far enough from the
///    last accepted one, so standing still doesn't accumulate metres;
///  * `_previous` is cleared on pause, so resuming never draws — or measures —
///    the straight line across wherever the walker went while paused;
///  * nothing is plotted until the signal reaches recording grade (or the
///    warm-up window expires), so the route is never anchored on the coarse
///    network fix a cold GPS start hands over first.
///
/// ## Surviving a pocket
///
/// A walk has to outlast the screen locking, another app coming to the front
/// and — the case that actually loses walks — the process being killed. Three
/// things carry it, and all three are turned on here and nowhere else:
///
///  * The position stream is opened with `background: true`, which is what puts
///    the Android foreground service and the iOS background-location flag in
///    play. It is opened at [start] and cancelled at [_stopStreams], and there
///    is no third place, so the notification and the blue indicator exist for
///    exactly the span of a walk.
///  * The clock is read from the wall rather than counted in ticks. A
///    `Timer.periodic` that misses a beat because the OS deferred it used to be
///    a second of somebody's walk quietly gone; now the timer only decides *how
///    often the screen updates*, and [_elapsedNow] decides what it says.
///  * Everything worth keeping is written to [RecordingJournal] as it happens,
///    so a walk the OS kills comes back on the next launch as something to
///    resume or save rather than as nothing at all.
///
/// One deliberate exception to "stop the instant it pauses": a paused walk
/// keeps its subscription, and therefore its foreground service. Dropping them
/// would cost the GNSS lock on every prayer stop, and — worse — Android 12+
/// forbids *starting* a foreground service from the background, so a walker who
/// paused with the phone in a pocket could never resume. A pause is inside a
/// recording, not outside it, and the notification on screen says so.
class RecordingController extends Notifier<RecordingState> {
  StreamSubscription<LocationFix>? _subscription;
  Timer? _ticker;
  AppLifecycleListener? _lifecycle;

  /// The last *accepted* fix. Null before the first one and immediately after
  /// a resume, which is what breaks the segment across a pause.
  LocationFix? _previous;

  /// Altitude of the last accepted fix, for the elevation delta.
  double? _previousAltitude;

  /// When the warm-up gate opened. Null once the gate has closed for good.
  DateTime? _warmUpStartedAt;

  /// The clock, kept as two halves so it can be read off the wall.
  ///
  /// [_movingSince] is when the current *moving* segment began, and null while
  /// paused; [_movingBefore] is everything banked by earlier segments and by a
  /// walk resumed from disk. Elapsed is the sum — see [_elapsedNow].
  ///
  /// This used to be a counter incremented once per tick, which was correct
  /// exactly as long as every tick fired. Backgrounded, they do not: Android
  /// defers timers under Doze and iOS can hold the app briefly between location
  /// callbacks, and every skipped beat was a second of walking that silently
  /// never happened. Reading the wall clock cannot skip.
  DateTime? _movingSince;
  Duration _movingBefore = Duration.zero;

  /// What paces the verses. Null when scripture is switched off for this walk.
  /// Always a distance trigger to begin with, even when steps were asked for —
  /// see [_armScripture].
  CadenceTrigger? _cadence;

  /// The trigger's own way of asking to be evaluated.
  ///
  /// A distance trigger never pushes — it is evaluated from [_onFix], which is
  /// the only place the distance changes. A step trigger pushes from the
  /// pedometer, and this subscription is the whole reason step cadence works
  /// on a walk with no usable fixes at all.
  StreamSubscription<void>? _cadenceDue;

  /// The library this walk draws from, and the order it draws in.
  ///
  /// [_queue] is the whole library in draw order: drawing walks the cursor
  /// forward and never looks back, which is what stops a verse arriving twice
  /// on one walk. Running off the end re-ranks rather than stopping — an hour on
  /// the road should not go quiet because the library is short.
  ///
  /// The ordering itself is [rankScripturePrompts], which reads the member's
  /// delivery history: unseen passages first, then least recently seen, with
  /// anything received in the last month held back. This used to be a plain
  /// shuffle rebuilt from nothing at the start of every walk, which is why a
  /// passage came back on the second walk almost every time. The queue is still
  /// per-walk; what it is built *from* is no longer.
  List<ScripturePrompt> _library = const [];
  List<ScripturePrompt> _queue = const [];
  int _cursor = 0;
  final math.Random _shuffle = math.Random();

  /// Set when the notifier is torn down, so the async scripture work — a
  /// library fetch, a sensor probe — knows not to touch `state` on the way out.
  bool _disposed = false;

  static const _tag = 'PW-REC';

  // The thresholds live in [LocationQuality] rather than here, so the recorder
  // and the location service cannot drift into disagreeing about how accurate
  // a fix has to be.

  @override
  RecordingState build() {
    _watchLifecycle();
    // A Notifier can be disposed while a walk is in flight (the provider is
    // refreshed, the container is torn down). Without this the subscription
    // and ticker outlive it and keep waking the GPS.
    ref.onDispose(() {
      _disposed = true;
      _lifecycle?.dispose();
      _lifecycle = null;
      _stopStreams();
    });
    return const RecordingState();
  }

  /// Watches the app going away and coming back.
  ///
  /// Two jobs, and neither of them is "restart the recording" — the whole point
  /// of the background configuration is that nothing needs restarting.
  ///
  ///  * **Leaving** is the last moment before a kill, so the journal is forced
  ///    to disk rather than left to its throttle. This is the write that makes
  ///    the difference between recovering the walk up to the doorstep and
  ///    recovering it up to four seconds earlier.
  ///  * **Coming back** re-opens the position stream only if there is a live
  ///    walk that somehow has none — a stream that errored to completion while
  ///    we were away. [_openStream] refuses to open a second one, which is the
  ///    guard that keeps a resume from doubling the fixes and therefore the
  ///    distance.
  ///
  /// Constructing an [AppLifecycleListener] needs the widgets binding, which a
  /// pure-Dart test may not have. Failing to watch the lifecycle costs
  /// robustness, never the walk, so it is caught and shrugged off.
  void _watchLifecycle() {
    try {
      _lifecycle = AppLifecycleListener(
        onHide: _journalNow,
        onPause: _journalNow,
        onDetach: _journalNow,
        onRestart: _reopenStreamIfLost,
        onResume: _reopenStreamIfLost,
      );
    } catch (error) {
      AppLogger.info(_tag, 'lifecycle unavailable (${error.runtimeType})');
    }
  }

  void _journalNow() {
    if (!state.isLive) return;
    unawaited(_journal.saveNow(_snapshot()));
  }

  void _reopenStreamIfLost() {
    if (!state.isLive || _subscription != null) return;
    AppLogger.info(_tag, 'position stream was lost — re-opening');
    _openStream();
  }

  RecordingJournal get _journal => ref.read(recordingJournalProvider);

  /// The chime, the haptic and the voice.
  ///
  /// Read here rather than from the live screen, and that move is the whole
  /// reason scripture reaches a walker whose phone is in a pocket. The
  /// announcement used to hang off a `ref.listen` in `LiveTrackingScreen`,
  /// which meant a verse only spoke while that screen happened to be built —
  /// so walking with the app on another tab, or with the phone locked and the
  /// screen disposed, delivered the marker in silence. The recorder outlives
  /// every screen, so announcing from here is the only place it can be right.
  ScriptureAnnouncer get _announcer => ref.read(scriptureAnnouncerProvider);

  // ----------------------------------------------------------- pre-flight ---

  void selectType(ActivityType type) {
    state = state.copyWith(type: type);
  }

  /// Called from the devotional reader's "Start a walk with this".
  ///
  /// [category] is carried alongside the title so scripture on the trail can
  /// prefer verses from the same collection the walk was started from.
  void carryDevotional(String title, {DevotionalCategory? category}) => state =
      state.copyWith(devotionalTitle: title, devotionalCategory: category);

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

    final service = ref.read(locationServiceProvider);
    final access = await service.ensureAccess();
    if (!access.canRecord) {
      state = state.copyWith(status: RecordingStatus.idle, access: access);
      return access;
    }

    // Everything else the platform wants is asked for *here* — after
    // when-in-use has been granted, and only because somebody pressed Start.
    // Neither of these can block the walk, so neither is allowed to fail it.
    await _askForBackgroundExtras(service);
    if (_disposed) return access;

    _previous = null;
    _previousAltitude = null;
    // The gate that kills the classic opening jump: a cold GPS start emits a
    // coarse network fix first, and anchoring the route on it puts the first
    // point hundreds of metres from where the walk actually began. Set after
    // the permission prompts, so a walker who reads them carefully does not
    // spend their warm-up window doing it.
    _warmUpStartedAt = DateTime.now();
    _movingBefore = Duration.zero;
    _movingSince = DateTime.now();

    // Snapshotted, not watched: what the walker decided before setting off is
    // what this walk runs on, and the live mute control edits the snapshot
    // rather than rewriting their stored default.
    final scripture = ref.read(scriptureSettingsProvider);

    state = state.copyWith(
      status: RecordingStatus.recording,
      startedAt: DateTime.now(),
      elapsed: Duration.zero,
      distanceMeters: 0,
      elevationGainMeters: 0,
      route: const [],
      waypoints: const [],
      warmingUp: true,
      scripture: scripture,
      scriptureFellBackToDistance: false,
      deliveredPrompts: const [],
      clearCurrentPrompt: true,
      clearDraft: true,
      clearAccuracy: true,
      // Precise clears the notice; approximate keeps it on screen.
      clearAccess: access.isPrecise,
      access: access.isPrecise ? null : access,
    );

    _armScripture(scripture);
    _openStream();
    _startTicker();
    // The first line of the journal. Written immediately rather than on the
    // throttle, because the interval between Start and the first fix is exactly
    // when a cold-started app is most likely to be killed.
    unawaited(_journal.saveNow(_snapshot()));
    return access;
  }

  /// The two permissions a walk in a pocket wants and does not need.
  ///
  /// Both are asked for once, here, and a refusal of either leaves an ordinary
  /// working recording behind:
  ///
  ///  * **Notifications** — Android 13+ will not display the foreground-service
  ///    notification without it. The service runs regardless; what is lost is
  ///    the walker being able to see that it is running.
  ///  * **Background location** — the separate, second location step Android
  ///    requires. It is only reached when when-in-use is already granted, only
  ///    from a press of Start, and only once per install: `request()` is a
  ///    no-op when the answer is already settled, and the flag covers the one
  ///    state (Android 10's re-askable denial) where it is not. Asking on every
  ///    walk is the nagging this is written to avoid.
  Future<void> _askForBackgroundExtras(LocationService service) async {
    try {
      await service.ensureNotificationAccess();

      final current = await service.backgroundAccess();
      if (current == BackgroundLocationAccess.granted ||
          current == BackgroundLocationAccess.notApplicable) {
        return;
      }
      if (await _journal.hasAskedForBackgroundAccess()) return;

      await _journal.noteAskedForBackgroundAccess();
      final result = await service.requestBackgroundAccess();
      AppLogger.info(_tag, 'background location: ${result.name}');
    } catch (error, stack) {
      // A permission plugin that throws must not be able to stop a walk.
      AppLogger.error(_tag, 'background permission step failed', error, stack);
    }
  }

  /// The only place a position stream is opened, and it refuses to open two.
  ///
  /// That guard is the whole of "nothing double-subscribes on resume": every
  /// path that might want a stream — [start], [resumeInterrupted], the
  /// lifecycle listener — comes through here, and a second subscription would
  /// mean every fix counted twice and a distance that runs at double speed.
  void _openStream() {
    if (_subscription != null) return;
    _subscription = ref
        .read(locationServiceProvider)
        // True for the whole of a recording and false everywhere else. This is
        // the flag that starts the Android foreground service and lets iOS keep
        // delivering with the screen off.
        .positionStream(background: true)
        .listen(
          _onFix,
          onError: (_) {/* A dropped fix is not fatal. */},
          // A stream that ends is a stream we may need to re-open when the app
          // next comes forward; leaving a dead subscription in place would stop
          // the lifecycle listener from noticing.
          onDone: () => _subscription = null,
        );
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), _onTick);
  }

  /// Moving time as of now, to the microsecond. Only the clock uses this.
  Duration get _elapsedExact {
    final since = _movingSince;
    if (since == null) return _movingBefore;
    return _movingBefore + DateTime.now().difference(since);
  }

  /// Moving time as anything outside this class should see it: whole seconds.
  ///
  /// Truncated on the way out rather than on the way in, so the fractions do
  /// survive a pause. Flooring [_movingBefore] itself would throw away up to a
  /// second on every stop, which on a prayer walk — the one activity where
  /// stopping repeatedly is the point — adds up to real minutes.
  Duration get _elapsedNow => Duration(seconds: _elapsedExact.inSeconds);

  void _onTick(Timer _) {
    if (state.status != RecordingStatus.recording) return;
    state = state.copyWith(elapsed: _elapsedNow);
    // Ordinary progress, so the throttle applies. The clock moving is the one
    // thing that changes on a walk where nothing else does — a walker standing
    // still under tree cover — and without this the journal for that walk would
    // never be written at all.
    _journal.save(_snapshot());
  }

  /// The walk as it stands, in the shape the journal writes and a relaunch
  /// reads back.
  InterruptedRecording _snapshot() => InterruptedRecording(
    type: state.type,
    startedAt: state.startedAt ?? DateTime.now(),
    lastSeenAt: DateTime.now(),
    elapsed: state.elapsed,
    distanceMeters: state.distanceMeters,
    elevationGainMeters: state.elevationGainMeters,
    route: state.route,
    waypoints: state.waypoints,
    intentions: state.intentions,
    deliveredPrompts: state.deliveredPrompts,
    scripture: state.scripture,
    devotionalTitle: state.devotionalTitle,
    devotionalCategory: state.devotionalCategory,
    wasPaused: state.isPaused,
  );

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
      // No distance moved, so a distance trigger has nothing new to say. A step
      // trigger might: this is the fix that turns `lastPoint` from null into a
      // place, and a threshold crossed before the walk had one is being held
      // for exactly this moment.
      _maybeDeliverPrompt();
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

    // Only here, after the totals have moved: this is the one branch that
    // changes the distance, and the cadence is measured against the distance.
    _maybeDeliverPrompt();
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
    // Bank the segment. Everything from here until resume belongs to nobody.
    _movingBefore = _elapsedExact;
    _movingSince = null;
    state = state.copyWith(
      status: RecordingStatus.paused,
      elapsed: _elapsedNow,
    );
    // A pause is a request for quiet as much as for the clock to stop, and the
    // walker may be nowhere near the screen when they make it.
    unawaited(_announcer.silence());
    unawaited(_journal.saveNow(_snapshot()));
  }

  void resume() {
    if (state.status != RecordingStatus.paused) return;
    _previous = null;
    _movingSince = DateTime.now();
    state = state.copyWith(status: RecordingStatus.recording);
    // A threshold crossed during the pause was held rather than consumed, and
    // on step cadence the next push may be a long way off — a walker who
    // paused, prayed and set off again should not have to walk another full
    // interval to collect what they had already earned.
    _maybeDeliverPrompt();
    unawaited(_journal.saveNow(_snapshot()));
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
    // Off the throttle: a deliberate act — a candle lit on the trail — is the
    // last thing that should be lost to a kill four seconds later.
    unawaited(_journal.saveNow(_snapshot()));
  }

  // ----------------------------------------------- scripture on the trail ---

  /// Sets up the verses for a walk. Never throws, never blocks, never fails in
  /// a way that costs the recording.
  ///
  /// The distance trigger is armed straight away even when steps were asked
  /// for. That is deliberate: distance needs nothing the recorder is not
  /// already measuring, so it can be armed synchronously, while a step sensor
  /// needs a permission dialog and a probe that can take seconds or never
  /// answer at all. Arming distance first and swapping the step trigger in when
  /// it reports ready means pressing Start is never held up by a sensor, and a
  /// device with no pedometer simply carries on in metres.
  void _armScripture(ScriptureSettings settings) {
    _useCadence(null);
    _library = const [];
    _queue = const [];
    _cursor = 0;

    // The one switch that suppresses arming. Everything else about scripture —
    // a missing sensor, a refused permission, an empty library, a walk with no
    // signal — degrades rather than disarms.
    if (!settings.enabled) return;

    final cadence = settings.cadence;
    _useCadence(
      DistanceCadenceTrigger(
        intervalMeters: cadence.source == CadenceSource.steps
            ? cadence.approximateMeters
            : cadence.intervalMeters,
      ),
    );

    unawaited(_loadLibrary());
    if (cadence.source == CadenceSource.steps) {
      unawaited(_armStepCadence(cadence));
    }
  }

  /// Installs a trigger and starts listening to whatever it pushes.
  ///
  /// Every change of trigger goes through here — arming, the swap to steps,
  /// tearing down — so the subscription can never outlive the trigger that
  /// owns it or be left pointing at a disposed one.
  void _useCadence(CadenceTrigger? trigger) {
    _cadenceDue?.cancel();
    _cadenceDue = null;
    _cadence?.dispose();
    _cadence = trigger;
    if (trigger == null) return;
    _cadenceDue = trigger.due.listen(
      (_) => _maybeDeliverPrompt(),
      // A sensor that fails after it started is a walk that stops getting
      // verses, and nothing worse than that.
      onError: (Object error) =>
          AppLogger.info(_tag, 'cadence signal failed (${error.runtimeType})'),
    );
  }

  /// Puts the walk's verses in memory.
  ///
  /// Reads the library provider, which the record screen has usually already
  /// warmed, and which falls back through the local cache to the set bundled
  /// in the binary — so this resolves with verses in airplane mode too. It is
  /// never awaited by [start]: a walk that cannot begin until a server answers
  /// is a walk that cannot begin in a valley.
  Future<void> _loadLibrary() async {
    List<ScripturePrompt> prompts;
    try {
      prompts = await ref.read(scriptureLibraryProvider.future);
    } catch (error) {
      // The repository does not throw; this is the provider being torn down
      // mid-flight, which costs verses and nothing else.
      AppLogger.info(_tag, 'no verses for this walk (${error.runtimeType})');
      return;
    }
    if (_disposed || !state.isLive) return;
    _library = prompts;
    _rebuildQueue();
  }

  /// Tries to upgrade the walk from distance to steps.
  ///
  /// This is the only path that asks for the motion permission, and it is only
  /// reached because the walker chose step cadence. An unavailable sensor is
  /// not an error — it leaves the distance trigger exactly where it was and
  /// raises a flag the live screen mentions once.
  Future<void> _armStepCadence(ScriptureCadence cadence) async {
    final trigger = ref.read(stepTriggerBuilderProvider)(cadence.intervalSteps);

    CadenceReadiness readiness;
    try {
      readiness = await trigger.prepare();
    } catch (error) {
      AppLogger.info(_tag, 'step cadence failed (${error.runtimeType})');
      readiness = CadenceReadiness.unavailable;
    }

    if (_disposed || !state.isLive) {
      trigger.dispose();
      return;
    }

    if (readiness == CadenceReadiness.ready) {
      // The interim distance trigger is discarded whole, and the step trigger
      // starts from the baseline its own probe just captured — so the swap can
      // neither carry a half-crossed threshold over nor count one twice. The
      // few steps taken during the probe are not counted towards the first
      // interval; three seconds of walking is about four steps, which is
      // cheaper than the alternative of holding up Start on a sensor.
      _useCadence(trigger);
      // The probe may have taken seconds, and on a walk with a sharp signal the
      // interim trigger will have been evaluated meanwhile. Ask the new one
      // once now rather than waiting for the next step sample, which on a
      // handset that reports in batches can be a while away.
      _maybeDeliverPrompt();
      return;
    }

    trigger.dispose();
    state = state.copyWith(scriptureFellBackToDistance: true);
  }

  /// Asks the cadence whether a verse is due, and delivers it if it is.
  ///
  /// Reached from two places now: an accepted fix that moved the distance, and
  /// a trigger that paced itself there. Both ask the same question through the
  /// same suppressions, so a step-paced walk and a distance-paced one deliver
  /// under identical conditions — the only difference is who does the asking.
  ///
  /// Nothing that happens in here may cost the recording, so the whole of it is
  /// caught: a walk is a thing being measured, and a verse is a courtesy.
  void _maybeDeliverPrompt() {
    try {
      _deliverIfDue();
    } catch (error, stack) {
      AppLogger.error(_tag, 'scripture delivery failed', error, stack);
    }
  }

  /// Every suppression is checked *before* the trigger is consulted, because
  /// consulting it advances it: asking during a pause and throwing the answer
  /// away would silently eat the verse the walker was owed on the far side.
  ///
  /// That ordering is also the answer to a step threshold crossed with nowhere
  /// to put the marker. A verse needs a place — [dropWaypoint] pins it to
  /// [RecordingState.lastPoint], and a walk that has not yet plotted a point
  /// has no truthful place to offer. So the threshold is **held, not dropped**:
  /// the trigger is never consulted, `_next` never advances, and the step
  /// counter stays above it — so the very next sample re-signals and the next
  /// accepted fix re-asks. The walker gets the verse late rather than never.
  ///
  /// A *stale* last point is treated differently and deliberately: it is
  /// delivered there. Sparse fixes are the ordinary condition of the walk this
  /// change exists for — a prayer walk under tree cover, slow enough to fall
  /// under the accumulation floor — and refusing to deliver at the last known
  /// point would reintroduce the silence by another route. The marker is a few
  /// metres behind the walker, which is the same tolerance every other waypoint
  /// on the walk already carries.
  void _deliverIfDue() {
    final trigger = _cadence;
    if (trigger == null) return;
    // Paused walks stay quiet, and so do walks that have finished.
    if (state.status != RecordingStatus.recording) return;
    // Nothing is plotted while the signal is still coarse, so there is nowhere
    // truthful to put a marker yet.
    if (state.warmingUp) return;
    final point = state.lastPoint;
    if (point == null) return;
    // The library has not landed yet. Leave the threshold unclaimed so the
    // first verse still arrives at the first interval it can.
    if (_library.isEmpty) return;

    if (!trigger.isDue(state.distanceMeters)) return;

    final prompt = _draw();
    if (prompt == null) return;

    // An ordinary waypoint, through the ordinary path — the reference as the
    // label, the text as the note. Nothing about persistence, the map or the
    // summary needs to know these ones arrived by themselves.
    //
    // The note is the *attributed* text: a waypoint outlives the prompt it came
    // from — it is JSONB on `activities`, with no translation of its own — so
    // the required mark is written into it here, at the one moment the edition
    // is still known. That is what makes the verse lists on the summary and
    // detail screens carry the mark without either screen knowing about
    // licensing.
    dropWaypoint(
      WaypointKind.scripture,
      label: prompt.reference,
      note: prompt.attributedBody,
    );

    // Remembered the moment it is handed over, so the next walk — and the next
    // rebuild of this walk's queue — can rank it as seen. Deliberately after
    // the waypoint and before nothing: it updates state synchronously, writes
    // to disk in the background and reaches the server when the walk ends. A
    // failure at any of those points costs the memory of the verse, never the
    // verse and never the recording.
    ref.read(scriptureHistoryProvider.notifier).record(prompt.id);

    final delivered = DeliveredPrompt(
      prompt: prompt,
      elapsed: state.elapsed,
      atMeters: state.distanceMeters,
    );
    state = state.copyWith(
      currentPrompt: delivered,
      deliveredPrompts: [...state.deliveredPrompts, delivered],
    );

    // Out loud, from here rather than from a screen — see [_announcer]. The
    // settings are this walk's snapshot, so the live mute control is obeyed.
    unawaited(
      _announcer.announce(
        prompt,
        sound: state.scripture.sound,
        voice: state.scripture.voice,
      ),
    );

    // Off the throttle, for the same reason a waypoint is: a verse is the part
    // of the walk somebody would actually miss.
    unawaited(_journal.saveNow(_snapshot()));
  }

  /// The next verse to deliver, or null when there is nothing to draw from.
  ScripturePrompt? _draw() {
    if (_library.isEmpty) return null;
    if (_cursor >= _queue.length) {
      final last = _queue.isEmpty ? null : _queue.last;
      // Re-ranked, not reshuffled — and against a history that now includes
      // everything this walk has already delivered, so the second pass through
      // a short library is ordered oldest-first rather than at random.
      _rebuildQueue();
      // A rebuild that opens on the verse that just went by reads as a repeat
      // even though the library was genuinely exhausted.
      if (_queue.length > 1 && last != null && _queue.first.id == last.id) {
        _queue = [..._queue.sublist(1, 2), _queue.first, ..._queue.sublist(2)];
      }
    }
    if (_queue.isEmpty) return null;
    return _queue[_cursor++];
  }

  /// Puts the library in draw order for this member and this walk.
  ///
  /// The ranking itself is [rankScripturePrompts] — a pure function, so what
  /// "fresh" means can be asserted directly rather than inferred from a
  /// simulated walk. What this method owns is the three things only the
  /// recorder knows: which theme was asked for, what the member has already
  /// been given, and how long a passage should rest.
  ///
  /// Theme preference is unchanged from before — "prefer" rather than "filter",
  /// so a themed walk works through its theme and then keeps going instead of
  /// falling silent at the end of a short collection.
  void _rebuildQueue() {
    _queue = rankScripturePrompts(
      library: _library,
      history: ref.read(scriptureHistoryProvider),
      preferred: state.scripture.category ?? state.devotionalCategory,
      cooldown: Duration(days: AppConfig.scriptureCooldownDays),
      random: _shuffle,
    );
    _cursor = 0;
  }

  /// Lets go of the card on screen. Ignoring a verse costs nothing, so this is
  /// what the auto-dismiss timer calls as well as the close button.
  void dismissPrompt() {
    if (state.currentPrompt == null) return;
    state = state.copyWith(clearCurrentPrompt: true);
  }

  /// The live screen's one-tap mute. Scoped to this walk — the stored default
  /// is left alone, because muting one walk is not the same as deciding never
  /// to hear another.
  void setScriptureMuted(bool muted) {
    state = state.copyWith(
      scripture: state.scripture.copyWith(sound: !muted, voice: !muted),
    );
    // Muting has to stop what is being said right now, or the control reads as
    // broken for the eight seconds it takes the verse to finish.
    if (muted) unawaited(_announcer.silence());
    if (state.isLive) unawaited(_journal.saveNow(_snapshot()));
  }

  /// Stops recording and assembles the draft the summary screen edits.
  void finish() {
    if (!state.isLive) return;
    // Reads the wall clock one last time before the segment is closed, so a
    // walk finished between ticks is not a second short.
    final elapsed = _elapsedNow;
    _stopStreams();
    final startedAt = state.startedAt ?? DateTime.now();
    state = state.copyWith(
      status: RecordingStatus.finished,
      warmingUp: false,
      elapsed: elapsed,
      draft: ActivityDraft(
        type: state.type,
        title: defaultTitle(state.type, startedAt),
        startedAt: startedAt,
        duration: elapsed,
        distanceMeters: state.distanceMeters,
        elevationGainMeters: state.elevationGainMeters,
        route: List.unmodifiable(state.route),
        waypoints: List.unmodifiable(state.waypoints),
        intentions: state.intentions,
      ),
    );

    // The walk is now a draft held in memory and shown on the summary screen,
    // which is a different kind of at-risk: losing it costs the walk again. So
    // the journal is *kept* until the draft is saved or deliberately discarded
    // — a crash on the summary screen still comes back as something to save.
    unawaited(_journal.saveNow(_snapshot()));

    // Fire-and-forget: the summary screen is already usable, and a walk must
    // never wait on a geocoding endpoint to be saveable.
    unawaited(_resolvePlaceName());
  }

  // ------------------------------------------------- the walk that was lost ---

  /// Picks an interrupted walk back up and carries on recording it.
  ///
  /// Everything measured is restored as it was, and one thing deliberately is
  /// not: `_previous` starts null, exactly as it does after a pause. That is
  /// what stops the first fix after a relaunch from drawing — and measuring —
  /// the straight line from wherever the walk died to wherever the walker is
  /// now, which on a walk resumed ten minutes later would be a phantom leg
  /// several hundred metres long.
  ///
  /// The clock resumes from the moving time that was banked, not from the wall
  /// clock since the walk began. Nobody knows whether the minutes the app was
  /// dead for were walked, and inventing them is worse than leaving them out.
  Future<LocationAccess> resumeInterrupted(InterruptedRecording walk) async {
    if (state.isLive) return state.access ?? LocationAccess.granted;

    state = state.copyWith(
      status: RecordingStatus.requesting,
      clearAccess: true,
    );

    final service = ref.read(locationServiceProvider);
    final access = await service.ensureAccess();
    if (!access.canRecord) {
      state = state.copyWith(status: RecordingStatus.idle, access: access);
      return access;
    }
    await _askForBackgroundExtras(service);
    if (_disposed) return access;

    _previous = null;
    _previousAltitude = null;
    // A resumed walk warms up again. The device has been asleep or dead; its
    // first fix is as cold as any other cold start, and anchoring the restored
    // route on it is precisely the jump the gate exists to prevent.
    _warmUpStartedAt = DateTime.now();
    _movingBefore = walk.elapsed;
    _movingSince = walk.wasPaused ? null : DateTime.now();

    state = RecordingState(
      type: walk.type,
      intentions: walk.intentions,
      status: walk.wasPaused
          ? RecordingStatus.paused
          : RecordingStatus.recording,
      devotionalTitle: walk.devotionalTitle,
      devotionalCategory: walk.devotionalCategory,
      scripture: walk.scripture,
      deliveredPrompts: walk.deliveredPrompts,
      startedAt: walk.startedAt,
      elapsed: walk.elapsed,
      distanceMeters: walk.distanceMeters,
      elevationGainMeters: walk.elevationGainMeters,
      route: walk.route,
      waypoints: walk.waypoints,
      warmingUp: true,
      access: access.isPrecise ? null : access,
    );

    _armScripture(walk.scripture);
    _openStream();
    _startTicker();
    // The journal now describes a *live* walk rather than a lost one, and it
    // keeps describing it for the rest of the recording. Deliberately no
    // `invalidate` here: re-reading would hand the record screen the walk that
    // is running right now and offer it back as unfinished. What stops the card
    // reappearing is the screen refusing to show one while a walk is live —
    // clearing the journal instead would throw away the recovery this walk is
    // itself an example of needing.
    unawaited(_journal.saveNow(_snapshot()));
    return access;
  }

  /// Treats an interrupted walk as finished, without recording another metre.
  ///
  /// The other half of the promise: a walker who has already got home does not
  /// want to resume, and their hour must not be the price of saying so. This
  /// puts the walk straight into the draft the summary screen edits, so it goes
  /// through exactly the same titling, visibility and save path as a walk that
  /// ended normally.
  void keepInterrupted(InterruptedRecording walk) {
    _stopStreams();
    state = RecordingState(
      type: walk.type,
      intentions: walk.intentions,
      status: RecordingStatus.finished,
      devotionalTitle: walk.devotionalTitle,
      devotionalCategory: walk.devotionalCategory,
      scripture: walk.scripture,
      deliveredPrompts: walk.deliveredPrompts,
      startedAt: walk.startedAt,
      elapsed: walk.elapsed,
      distanceMeters: walk.distanceMeters,
      elevationGainMeters: walk.elevationGainMeters,
      route: walk.route,
      waypoints: walk.waypoints,
      draft: ActivityDraft(
        type: walk.type,
        title: defaultTitle(walk.type, walk.startedAt),
        startedAt: walk.startedAt,
        duration: walk.elapsed,
        distanceMeters: walk.distanceMeters,
        elevationGainMeters: walk.elevationGainMeters,
        route: List.unmodifiable(walk.route),
        waypoints: List.unmodifiable(walk.waypoints),
        intentions: walk.intentions,
      ),
    );
    // The journal is deliberately left alone: this walk is now a draft on the
    // summary screen and still unsaved, which is exactly the state that needs a
    // net under it. `save` and `discard` are what clear it, once the walker has
    // said which one they meant.
    unawaited(_resolvePlaceName());
  }

  /// Throws an interrupted walk away. Only ever reached from a confirmation the
  /// walker gave — nothing in this class discards one by itself.
  Future<void> discardInterrupted() async {
    await _journal.clear();
    ref.invalidate(interruptedRecordingProvider);
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

  /// Who the finished walk will be for.
  ///
  /// Set on the summary screen, and seeded there from the member's standing
  /// default rather than assumed here. [ActivityDraft] starts at
  /// [ActivityVisibility.standard] so a walk that somehow reaches `save()`
  /// without passing the picker is still followers-only — the failure mode of
  /// this method never running has to be the private one.
  void setDraftVisibility(ActivityVisibility visibility) {
    final draft = state.draft;
    if (draft == null) return;
    state = state.copyWith(draft: draft.copyWith(visibility: visibility));
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

    // The walk is over, so this is the safe moment to tell the server what it
    // delivered — mirroring on the trail would put a network request at the
    // exact moment a verse is due. Deliberately here rather than in
    // [_stopStreams], which also runs while the notifier is being torn down,
    // where reading a provider is not allowed. Unawaited and unable to fail in
    // a way anyone sees: the device already holds the record, and whatever does
    // not land here is picked up by the next reconcile.
    if (!_disposed) {
      unawaited(ref.read(scriptureHistoryProvider.notifier).flush());
      // The walk has been saved or deliberately thrown away. This is the one
      // place the journal is cleared without the walker being asked, and it is
      // only reachable *after* they have decided — see [save] and [discard].
      unawaited(_journal.clear());
      ref.invalidate(interruptedRecordingProvider);
    }

    state = const RecordingState();
  }

  void _stopStreams() {
    _subscription?.cancel();
    // Cancelling is what takes the Android foreground service, its notification
    // and its wake lock away, and what turns off iOS's blue indicator. Nulling
    // it here rather than only in the `onDone` callback is what makes the
    // lifecycle listener's "is there still a stream?" question answerable.
    _subscription = null;
    _ticker?.cancel();
    _ticker = null;
    _previous = null;
    _previousAltitude = null;
    _warmUpStartedAt = null;
    _movingSince = null;
    // Nothing should still be speaking once a walk is over.
    if (!_disposed) unawaited(_announcer.silence());
    // Releases the step sensor subscription along with the GPS one — a walk
    // that has finished must not be left counting anything, or able to ask for
    // one more verse on the summary screen.
    _useCadence(null);
    _library = const [];
    _queue = const [];
    _cursor = 0;
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
