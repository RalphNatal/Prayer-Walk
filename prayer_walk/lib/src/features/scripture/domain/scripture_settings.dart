import '../../devotionals/domain/devotional.dart' show DevotionalCategory;
import 'scripture_prompt.dart';

/// What paces the arrivals.
///
/// Distance ships as the default because it is already being measured: no new
/// sensor, no new permission, works on every device, and works for a ride as
/// well as a walk. Steps are offered because "every 500 steps" is how people
/// actually think about a walk — but they cost a motion permission and are
/// genuinely absent on some hardware, so they are opt-in and fall back.
enum CadenceSource {
  distance('Distance'),
  steps('Steps');

  const CadenceSource(this.label);
  final String label;
}

/// The stride the step ⇄ distance conversion assumes.
///
/// A rough average for an adult walking pace. It is only ever used to *describe*
/// a distance interval in steps and the other way round, never to measure
/// anything — which is why every step figure shown against a distance cadence is
/// hedged with "about". Real stride varies with height, pace and terrain.
const double kAverageStrideMeters = 0.8;

/// How often a prompt should arrive, in whichever idiom the walker chose.
class ScriptureCadence {
  const ScriptureCadence({
    this.source = CadenceSource.distance,
    this.intervalMeters = 400,
    this.intervalSteps = 500,
  });

  final CadenceSource source;

  /// Metres between arrivals when [source] is [CadenceSource.distance].
  final double intervalMeters;

  /// Steps between arrivals when [source] is [CadenceSource.steps].
  final int intervalSteps;

  /// The two offered presets, named in both idioms so the mapping is visible
  /// rather than hidden: roughly 500 steps is roughly 400 m.
  static const gentle = ScriptureCadence(intervalMeters: 400, intervalSteps: 500);
  static const spacious = ScriptureCadence(
    intervalMeters: 800,
    intervalSteps: 1000,
  );

  /// The step count this distance interval works out at, for describing a
  /// distance cadence in the idiom the walker asked for.
  int get approximateSteps => (intervalMeters / kAverageStrideMeters).round();

  /// The distance this step interval works out at — used when the step sensor
  /// turns out to be missing and the walk falls back to distance.
  double get approximateMeters => intervalSteps * kAverageStrideMeters;

  ScriptureCadence copyWith({
    CadenceSource? source,
    double? intervalMeters,
    int? intervalSteps,
  }) {
    return ScriptureCadence(
      source: source ?? this.source,
      intervalMeters: intervalMeters ?? this.intervalMeters,
      intervalSteps: intervalSteps ?? this.intervalSteps,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ScriptureCadence &&
      other.source == source &&
      other.intervalMeters == intervalMeters &&
      other.intervalSteps == intervalSteps;

  @override
  int get hashCode => Object.hash(source, intervalMeters, intervalSteps);
}

/// Everything the walker has decided about scripture on the trail.
///
/// One object serves as both the global default (Settings) and the per-walk
/// choice (the record screen), because they are the same decision made at two
/// moments — the per-walk one simply starts from the global one.
class ScriptureSettings {
  const ScriptureSettings({
    this.enabled = true,
    this.cadence = ScriptureCadence.gentle,
    this.category,
    this.sound = true,
    this.voice = true,
    this.showTranslation = true,
  });

  final bool enabled;
  final ScriptureCadence cadence;

  /// The theme to draw from. Null means the whole library.
  final DevotionalCategory? category;

  /// The arrival chime. The haptic is not separately switchable — it is the
  /// part that still works with the phone in a pocket and the ringer off.
  final bool sound;

  /// Reads the verse aloud. On by default: a phone in a pocket is the ordinary
  /// case, and a verse nobody sees is the failure this feature exists to avoid.
  final bool voice;

  /// Whether the translation credit is drawn under the text.
  final bool showTranslation;

  ScriptureSettings copyWith({
    bool? enabled,
    ScriptureCadence? cadence,
    DevotionalCategory? category,
    bool? sound,
    bool? voice,
    bool? showTranslation,
    bool clearCategory = false,
  }) {
    return ScriptureSettings(
      enabled: enabled ?? this.enabled,
      cadence: cadence ?? this.cadence,
      category: clearCategory ? null : (category ?? this.category),
      sound: sound ?? this.sound,
      voice: voice ?? this.voice,
      showTranslation: showTranslation ?? this.showTranslation,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ScriptureSettings &&
      other.enabled == enabled &&
      other.cadence == cadence &&
      other.category == category &&
      other.sound == sound &&
      other.voice == voice &&
      other.showTranslation == showTranslation;

  @override
  int get hashCode =>
      Object.hash(enabled, cadence, category, sound, voice, showTranslation);
}

/// A prompt that has arrived on this walk, and where in the walk it landed.
///
/// A fresh instance per arrival, so the live screen can key its announcement
/// off identity — the same passage cannot arrive twice in a walk, but a
/// rebuild must not re-announce the one already on screen.
class DeliveredPrompt {
  const DeliveredPrompt({
    required this.prompt,
    required this.elapsed,
    required this.atMeters,
  });

  final ScripturePrompt prompt;

  /// How far into the walk it arrived — the same clock the waypoint carries.
  final Duration elapsed;
  final double atMeters;
}
