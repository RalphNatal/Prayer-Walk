/// Whether a trigger can actually run on the device in hand.
enum CadenceReadiness {
  ready,

  /// The sensor this trigger needs is missing, or the permission it needs was
  /// refused. The caller is expected to fall back rather than to fail.
  unavailable,
}

/// Decides when the next thing is due on a walk.
///
/// Pulled out as an interface for one reason: "every 500 steps" and "every
/// 400 m" are the same intention expressed in two idioms, and only one of them
/// can be measured on every device. Distance is already being accumulated by
/// the recorder — no new sensor, no new permission, works while cycling, works
/// on hardware with no pedometer at all. Steps need `ACTIVITY_RECOGNITION` on
/// Android 10+, `NSMotionUsageDescription` on iOS, a baseline subtraction
/// (Android reports steps since the device last booted, not since the walk
/// began), and are simply absent on some handsets.
///
/// So distance is what ships and what everything falls back to; steps are an
/// opt-in that reports its own unavailability rather than failing quietly.
abstract class CadenceTrigger {
  /// Acquires whatever the trigger needs — permissions, sensors, a baseline —
  /// and says whether it can run. Never throws: a trigger that cannot prepare
  /// answers [CadenceReadiness.unavailable].
  Future<CadenceReadiness> prepare();

  /// Fires when the trigger has advanced *on its own* and may now be due.
  ///
  /// This exists because a trigger paced by something other than distance has
  /// no other way to be heard. The recorder used to ask [isDue] from exactly
  /// one place — after an accepted fix had moved the total — which is the right
  /// question for a distance trigger and the wrong one for a step trigger: the
  /// pedometer could be counting perfectly while no verse arrived, because
  /// nobody ever put the question to it. A walk with sparse fixes, or slow
  /// enough that fixes fell under the accumulation floor, simply went quiet.
  ///
  /// So a push-paced trigger says when to ask. It is a signal, not an answer:
  /// the recorder still checks every suppression and still consults [isDue],
  /// which is what keeps the two invariants below intact. A trigger that is
  /// genuinely paced by distance has nothing to push and returns an empty
  /// stream — it continues to be evaluated on position updates.
  ///
  /// Broadcast, so a listener arriving late (the step trigger is swapped in
  /// after its sensor probe) is not a second-subscription error.
  Stream<void> get due;

  /// Whether something is due now, given how far the walk has come.
  ///
  /// Two properties every implementation owes its caller:
  ///
  ///  * **at most one per call.** A single GPS fix can jump kilometres — a
  ///    tunnel, a bad multipath fix, a phone that woke up somewhere else — and
  ///    a walker must not be handed seven verses at once because of it.
  ///  * **no backlog.** Whatever was skipped by that jump is skipped for good;
  ///    the next one is due at the next threshold *above* where the walk
  ///    actually is.
  ///
  /// The same two hold for a [due] signal that arrives in a batch: a pedometer
  /// that went quiet and handed over four intervals at once is one prompt.
  bool isDue(double distanceMeters);

  /// Back to the start of the walk. Called when a recording begins.
  void reset();

  void dispose();
}

/// The shipped default: one prompt each time the walk crosses another multiple
/// of [intervalMeters].
///
/// Thresholds are absolute multiples rather than "distance since the last one",
/// so a pause, a resume, or a stretch of walk with no fixes cannot drift the
/// spacing — after 830 m the next one is still due at 1200 m, not at 1230 m.
class DistanceCadenceTrigger implements CadenceTrigger {
  DistanceCadenceTrigger({required this.intervalMeters})
    : _next = intervalMeters;

  final double intervalMeters;

  /// The distance the next prompt is owed at. Starts at one full interval, not
  /// at zero: the walk is allowed to begin before it is spoken to.
  double _next;

  @override
  Future<CadenceReadiness> prepare() async => CadenceReadiness.ready;

  /// Nothing to push. Distance moves only when the recorder accepts a fix, and
  /// the recorder already evaluates there — a signal from here would say
  /// nothing the caller does not already know.
  @override
  Stream<void> get due => const Stream<void>.empty();

  @override
  bool isDue(double distanceMeters) {
    if (intervalMeters <= 0) return false;
    if (distanceMeters < _next) return false;
    // The line that makes one jump one verse: the next threshold is the first
    // multiple strictly above where the walk now is, so everything the jump
    // flew over is gone rather than queued.
    _next = ((distanceMeters ~/ intervalMeters) + 1) * intervalMeters;
    return true;
  }

  @override
  void reset() => _next = intervalMeters;

  @override
  void dispose() {}
}
