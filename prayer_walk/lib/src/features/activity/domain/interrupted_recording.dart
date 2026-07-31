import 'package:latlong2/latlong.dart';

import '../../devotionals/domain/devotional.dart' show DevotionalCategory;
import '../../scripture/domain/scripture_settings.dart';
import 'activity.dart';

/// A walk that was still being recorded when the app stopped running.
///
/// This is the answer to the worst outcome this feature has: an hour on the
/// road, the phone in a pocket, and Android deciding it needs the memory. The
/// recorder writes its running state to disk as it accumulates, and on the next
/// launch whatever is on disk arrives here — not as a walk that has been
/// silently resurrected, but as something to be *offered back*. The walker
/// decides whether it is finished or whether they are still on it.
///
/// Everything on it is what the live state held, minus the things that mean
/// nothing across a restart: the signal reading, the warm-up gate, the card
/// currently on screen. [wasPaused] survives because resuming into a running
/// clock a walker had deliberately stopped would quietly add time they did not
/// walk.
class InterruptedRecording {
  const InterruptedRecording({
    required this.type,
    required this.startedAt,
    required this.lastSeenAt,
    required this.elapsed,
    required this.distanceMeters,
    required this.elevationGainMeters,
    required this.route,
    required this.waypoints,
    required this.intentions,
    required this.deliveredPrompts,
    required this.scripture,
    this.devotionalTitle,
    this.devotionalCategory,
    this.wasPaused = false,
  });

  final ActivityType type;

  /// When the walk began — the wall clock, so the summary titles it correctly.
  final DateTime startedAt;

  /// The last moment the recorder managed to write anything down. The gap
  /// between this and now is how long the walk was dead for, and it is the one
  /// honest thing to show a walker deciding whether they are still on it.
  final DateTime lastSeenAt;

  /// Moving time, exactly as it was measured. Deliberately *not* topped up with
  /// the wall-clock time the app spent dead: nobody knows whether the walker
  /// was still walking, and inventing minutes is worse than under-reporting
  /// them. This is the same rule a pause already follows.
  final Duration elapsed;

  final double distanceMeters;
  final double elevationGainMeters;
  final List<LatLng> route;
  final List<Waypoint> waypoints;
  final List<PrayerIntention> intentions;

  /// What scripture had already given them. Carried so a resumed walk does not
  /// re-deliver the passage it delivered ten minutes ago, and so the verses
  /// read on the way are still on the summary.
  final List<DeliveredPrompt> deliveredPrompts;

  /// The settings *that walk* was running under, including a live mute.
  final ScriptureSettings scripture;

  final String? devotionalTitle;
  final DevotionalCategory? devotionalCategory;

  /// Whether the walk was paused when the lights went out.
  final bool wasPaused;

  /// How long ago the recorder last managed to write.
  Duration get age => DateTime.now().difference(lastSeenAt);

  /// Whether there is enough here to be worth putting in front of anybody.
  ///
  /// The floor is deliberately low but not zero. A walk with a traced route, or
  /// one that ran long enough to have measured something, is always offered —
  /// that is the promise. A press of Start followed immediately by a crash,
  /// with no fix ever accepted and nothing on the clock, is not a lost walk; it
  /// is a lost button press, and offering to "resume" it would be noise dressed
  /// up as care.
  bool get isWorthOffering =>
      route.isNotEmpty || elapsed >= const Duration(seconds: 30);

  /// Whether this is stale enough that resuming makes no sense.
  ///
  /// A walk the app lost six hours ago is over however it ended. It is still
  /// offered — never silently dropped — but as something to save, not to carry
  /// on with, because the gap in the trace would be the larger part of it.
  bool get isTooOldToResume => age >= const Duration(hours: 6);
}
