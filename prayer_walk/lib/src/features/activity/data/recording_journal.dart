import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/app_logger.dart';
import '../../devotionals/data/devotional_row_mapper.dart'
    show devotionalCategoryFrom;
import '../../scripture/data/scripture_row_mapper.dart';
import '../../scripture/domain/scripture_settings.dart';
import '../domain/interrupted_recording.dart';
import 'activity_row_mapper.dart';

/// The walk on disk, written while it is still happening.
///
/// Everything else about a recording lives in memory, which is the right place
/// for it right up to the moment Android decides it needs the memory back. A
/// walk is an hour of somebody's morning that cannot be repeated, so this is
/// the one part of the recorder that assumes it is about to be killed.
///
/// Three properties it has to have, and each one shapes the code:
///
///  * **Written as it accumulates.** Not at the end — the end is exactly the
///    moment that never arrives. [save] is called on every meaningful change.
///  * **Cheap enough to call constantly.** Which is why [save] coalesces:
///    ordinary progress is written at most once every [_interval], and the last
///    snapshot handed over always wins. Moments that would hurt to lose —
///    a waypoint, a verse, a pause, the end — go through [saveNow] and skip the
///    throttle.
///  * **Unable to break a walk.** Nothing here throws and nothing here is
///    awaited on the recording path. A disk that will not take the write costs
///    the recovery, never the recording.
///
/// The route, waypoints and intentions are written in the same JSON shape the
/// `activities` row uses (see `activity_row_mapper.dart`) so that the thing on
/// disk is one step from the thing that gets saved, and there is only one
/// definition of what a waypoint looks like.
class RecordingJournal {
  RecordingJournal();

  static const _tag = 'PW-REC';
  static const _key = 'recording.inProgress.v1';
  static const _askedKey = 'recording.backgroundAsked.v1';

  /// How often ordinary progress reaches the disk.
  ///
  /// At the recorder's five-metre filter a brisk walk produces a fix every
  /// three or four seconds, so this is roughly "every other fix". Losing four
  /// seconds of a walk to a kill is losing a few metres; writing sixty
  /// kilobytes of JSON on every fix for an hour is a battery cost with nothing
  /// to show for it.
  static const _interval = Duration(seconds: 4);

  Timer? _timer;

  /// The most recent snapshot nobody has written yet. Held unencoded, because
  /// [save] is called about once a second and encoding walks the whole route —
  /// there is no reason to build a two-thousand-point list for a snapshot the
  /// throttle is about to replace. Overwritten rather than queued: an older
  /// state of the same walk has no value once a newer one exists.
  InterruptedRecording? _pending;

  DateTime? _lastWrite;
  bool _disposed = false;

  /// Records progress, subject to the throttle. Never awaited by the recorder.
  void save(InterruptedRecording snapshot) {
    if (_disposed) return;
    _pending = snapshot;

    final last = _lastWrite;
    if (last != null && DateTime.now().difference(last) < _interval) {
      _timer ??= Timer(_interval, _flush);
      return;
    }
    unawaited(_flush());
  }

  /// Records progress immediately, for the changes that would be felt if they
  /// were lost: a prayer marked, a verse delivered, a pause, the end of a walk.
  Future<void> saveNow(InterruptedRecording snapshot) {
    if (_disposed) return Future.value();
    _pending = snapshot;
    return _flush();
  }

  /// What was on disk when the app started, or null if there was nothing —
  /// which is the ordinary case, because a walk that ended properly clears it.
  ///
  /// Anything unreadable is treated as nothing and removed. A journal written
  /// by an older build, or half-written by a kill mid-flush, must not be able
  /// to stop the app from starting.
  Future<InterruptedRecording?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return null;
      final decoded = _decode(jsonDecode(raw) as Map<String, dynamic>);
      if (decoded == null || !decoded.isWorthOffering) {
        await clear();
        return null;
      }
      return decoded;
    } catch (error) {
      AppLogger.warn(_tag, 'unfinished walk unreadable — discarding', error);
      await clear();
      return null;
    }
  }

  /// Forgets the in-progress walk. Called when one is saved, discarded, or
  /// resumed into the live recorder — at which point the live recorder starts
  /// writing its own.
  Future<void> clear() async {
    _timer?.cancel();
    _timer = null;
    _pending = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (error) {
      AppLogger.warn(_tag, 'could not clear the unfinished walk', error);
    }
  }

  // -------------------------------------- the other thing this remembers ---
  //
  // A single boolean, kept here rather than in a file of its own because it is
  // the recorder's local state and one flag does not earn a store.

  /// Whether the walker has already been asked, once, for background location.
  ///
  /// The permission itself is the source of truth for *what was answered*; this
  /// only answers "has the question been put to them", which the platform does
  /// not record. Without it, Android 10's re-askable denial would produce a
  /// system dialog at the start of every single walk.
  Future<bool> hasAskedForBackgroundAccess() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_askedKey) ?? false;
    } catch (_) {
      // Unreadable reads as "not yet asked": one extra dialog is a smaller
      // failure than a permission nobody is ever offered.
      return false;
    }
  }

  Future<void> noteAskedForBackgroundAccess() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_askedKey, true);
    } catch (error) {
      AppLogger.info(_tag, 'could not note the background prompt ($error)');
    }
  }

  /// Stops the throttle timer. The pending snapshot is written on the way out —
  /// disposal usually means the walk is over, but it can also mean the provider
  /// was torn down mid-walk, and that is the case this exists for.
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    if (_pending != null) unawaited(_write(_pending!));
    _pending = null;
  }

  Future<void> _flush() async {
    _timer?.cancel();
    _timer = null;
    final snapshot = _pending;
    if (snapshot == null) return;
    _pending = null;
    _lastWrite = DateTime.now();
    await _write(snapshot);
  }

  Future<void> _write(InterruptedRecording snapshot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(_encode(snapshot)));
    } catch (error) {
      // The recording is unaffected; only its recoverability is. Reported at
      // warn rather than error because there is nothing the walker can do and
      // nothing that has gone wrong with their walk.
      AppLogger.warn(_tag, 'could not journal the walk in progress', error);
    }
  }

  // --------------------------------------------------------------- shapes ---

  static Map<String, dynamic> _encode(InterruptedRecording snapshot) => {
    'type': snapshot.type.name,
    'started_at': snapshot.startedAt.toIso8601String(),
    'last_seen_at': snapshot.lastSeenAt.toIso8601String(),
    'elapsed_seconds': snapshot.elapsed.inSeconds,
    'distance_meters': snapshot.distanceMeters,
    'elevation_gain_meters': snapshot.elevationGainMeters,
    'route': encodeRoute(snapshot.route),
    'waypoints': encodeWaypoints(snapshot.waypoints),
    'intentions': encodeIntentions(snapshot.intentions),
    'was_paused': snapshot.wasPaused,
    'devotional_title': snapshot.devotionalTitle,
    'devotional_category': snapshot.devotionalCategory?.name,
    'scripture': _encodeScripture(snapshot.scripture),
    // The whole prompt, not just its id: the library it came from may have
    // changed, gone offline, or been re-ranked by the time this is read, and a
    // verse the walker was given is theirs whatever the server now says.
    'delivered': [
      for (final delivered in snapshot.deliveredPrompts)
        {
          'prompt': scripturePromptToRow(delivered.prompt),
          'elapsed_seconds': delivered.elapsed.inSeconds,
          'at_meters': delivered.atMeters,
        },
    ],
  };

  static InterruptedRecording? _decode(Map<String, dynamic> json) {
    final startedAt = DateTime.tryParse((json['started_at'] as String?) ?? '');
    if (startedAt == null) return null;

    return InterruptedRecording(
      type: activityTypeFrom(json['type'] as String?),
      startedAt: startedAt,
      lastSeenAt:
          DateTime.tryParse((json['last_seen_at'] as String?) ?? '') ??
          startedAt,
      elapsed: Duration(
        seconds: (json['elapsed_seconds'] as num?)?.toInt() ?? 0,
      ),
      distanceMeters: (json['distance_meters'] as num?)?.toDouble() ?? 0,
      elevationGainMeters:
          (json['elevation_gain_meters'] as num?)?.toDouble() ?? 0,
      route: decodeRoute(json['route']),
      // The synthetic id prefix these two take is only ever used as a widget
      // key, and an unfinished walk has no id of its own to lend them.
      waypoints: decodeWaypoints(json['waypoints'], 'resumed'),
      intentions: decodeIntentions(json['intentions'], 'resumed', startedAt),
      deliveredPrompts: _decodeDelivered(json['delivered']),
      scripture: _decodeScripture(json['scripture']),
      devotionalTitle: (json['devotional_title'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['devotional_title'] as String).trim(),
      devotionalCategory: json['devotional_category'] == null
          ? null
          : devotionalCategoryFrom(json['devotional_category'] as String?),
      wasPaused: json['was_paused'] == true,
    );
  }

  static Map<String, dynamic> _encodeScripture(ScriptureSettings settings) => {
    'enabled': settings.enabled,
    'source': settings.cadence.source.name,
    'interval_meters': settings.cadence.intervalMeters,
    'interval_steps': settings.cadence.intervalSteps,
    'category': settings.category?.name,
    'sound': settings.sound,
    'voice': settings.voice,
    'show_translation': settings.showTranslation,
  };

  static ScriptureSettings _decodeScripture(Object? raw) {
    if (raw is! Map) return const ScriptureSettings();
    final json = Map<String, dynamic>.from(raw);
    return ScriptureSettings(
      enabled: json['enabled'] != false,
      cadence: ScriptureCadence(
        source: CadenceSource.values.firstWhere(
          (s) => s.name == json['source'],
          orElse: () => CadenceSource.distance,
        ),
        intervalMeters: (json['interval_meters'] as num?)?.toDouble() ?? 400,
        intervalSteps: (json['interval_steps'] as num?)?.toInt() ?? 500,
      ),
      category: json['category'] == null
          ? null
          : devotionalCategoryFrom(json['category'] as String?),
      sound: json['sound'] != false,
      voice: json['voice'] != false,
      showTranslation: json['show_translation'] != false,
    );
  }

  static List<DeliveredPrompt> _decodeDelivered(Object? raw) {
    if (raw is! List) return const [];
    final out = <DeliveredPrompt>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final prompt = item['prompt'];
      if (prompt is! Map) continue;
      final prompts = scripturePromptsFromRows([prompt]);
      // `scripturePromptsFromRows` drops anything with no text — a prompt that
      // cannot be read is not one that was delivered.
      if (prompts.isEmpty) continue;
      out.add(
        DeliveredPrompt(
          prompt: prompts.single,
          elapsed: Duration(
            seconds: (item['elapsed_seconds'] as num?)?.toInt() ?? 0,
          ),
          atMeters: (item['at_meters'] as num?)?.toDouble() ?? 0,
        ),
      );
    }
    return out;
  }
}

/// One journal for the app, disposed with the container so a pending write is
/// never simply dropped.
final recordingJournalProvider = Provider<RecordingJournal>((ref) {
  final journal = RecordingJournal();
  ref.onDispose(journal.dispose);
  return journal;
});

/// The unfinished walk waiting to be offered back, read once per launch.
///
/// A [FutureProvider] rather than something the recorder hydrates into itself,
/// and that is the whole design: an interrupted walk must never resume by
/// itself. It sits here until the walker says what to do with it, because
/// silently restarting a recording — the GPS, the notification, the clock — for
/// somebody who has finished walking and just opened the app to read the feed
/// would be a worse failure than the one it is recovering from.
final interruptedRecordingProvider = FutureProvider<InterruptedRecording?>(
  (ref) => ref.watch(recordingJournalProvider).read(),
);
