import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../auth/data/auth_providers.dart';
import '../domain/activity.dart';
import 'location_service.dart';
import 'mock_activity_repository.dart';

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

  /// Why the last [RecordingController.start] failed, when it did. Null while
  /// things are fine.
  final LocationAccess? access;

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
    bool clearDraft = false,
    bool clearDevotional = false,
    bool clearAccess = false,
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
/// Two invariants the tests of "believable stats" rest on:
///  * a fix is only *accepted* if it is accurate enough and far enough from the
///    last accepted one, so standing still doesn't accumulate metres;
///  * `_previous` is cleared on pause, so resuming never draws — or measures —
///    the straight line across wherever the walker went while paused.
class RecordingController extends Notifier<RecordingState> {
  StreamSubscription<LocationFix>? _subscription;
  Timer? _ticker;

  /// The last *accepted* fix. Null before the first one and immediately after
  /// a resume, which is what breaks the segment across a pause.
  LocationFix? _previous;

  /// Altitude of the last accepted fix, for the elevation delta.
  double? _previousAltitude;

  /// Worse than this and the fix is noise, not a position.
  static const _maxAccuracyMeters = 25.0;

  /// Below this, a "movement" is GPS jitter. The platform's `distanceFilter`
  /// already screens most of it; this catches the rest.
  static const _minStepMeters = 3.0;

  /// GPS altitude wanders by several metres at rest. Only climbs above this
  /// count toward the gain.
  static const _minClimbMeters = 1.5;

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
  /// throws for a denial, since a denial is an ordinary answer.
  Future<LocationAccess> start() async {
    if (state.isLive) return LocationAccess.granted;

    state = state.copyWith(
      status: RecordingStatus.requesting,
      clearAccess: true,
    );

    final access = await ref.read(locationServiceProvider).ensureAccess();
    if (access != LocationAccess.granted) {
      state = state.copyWith(status: RecordingStatus.idle, access: access);
      return access;
    }

    _previous = null;
    _previousAltitude = null;
    state = state.copyWith(
      status: RecordingStatus.recording,
      startedAt: DateTime.now(),
      elapsed: Duration.zero,
      distanceMeters: 0,
      elevationGainMeters: 0,
      route: const [],
      waypoints: const [],
      clearDraft: true,
      clearAccess: true,
    );

    _subscription = ref
        .read(locationServiceProvider)
        .positionStream()
        .listen(_onFix, onError: (_) {/* A dropped fix is not fatal. */});

    _ticker = Timer.periodic(const Duration(seconds: 1), _onTick);
    return LocationAccess.granted;
  }

  void _onTick(Timer _) {
    if (state.status != RecordingStatus.recording) return;
    state = state.copyWith(elapsed: state.elapsed + const Duration(seconds: 1));
  }

  /// Accumulates one position into the running totals — the whole of the
  /// "believable stats" policy lives here.
  void _onFix(LocationFix fix) {
    // Paused: stay subscribed (re-acquiring a lock is slow and battery-hungry)
    // but consume nothing.
    if (state.status != RecordingStatus.recording) return;

    // A wide accuracy radius means the position could be anywhere in it.
    if (fix.accuracyMeters > _maxAccuracyMeters) return;

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
    if (step < _minStepMeters) return;

    final climb = fix.altitudeMeters - (_previousAltitude ?? fix.altitudeMeters);

    _previous = fix;
    _previousAltitude = fix.altitudeMeters;
    state = state.copyWith(
      route: [...state.route, fix.point],
      distanceMeters: state.distanceMeters + step,
      elevationGainMeters: climb > _minClimbMeters
          ? state.elevationGainMeters + climb
          : state.elevationGainMeters,
    );
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
