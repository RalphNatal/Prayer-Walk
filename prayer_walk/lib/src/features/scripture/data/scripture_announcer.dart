import 'dart:async';
import 'dart:ui' show FlutterView;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../../core/utils/app_logger.dart';
import '../domain/scripture_prompt.dart';

/// How a verse arrives in the world outside the screen: a chime, a haptic, and
/// — because the phone is usually in a pocket — a voice.
///
/// The single rule this class is built around: **a lost verse must never cost a
/// recorded walk**. Every platform call is lazy, wrapped, and allowed to fail
/// silently. A device with no text-to-speech engine, a locked audio session, a
/// missing haptic motor and a test environment with no plugins at all all
/// produce the same outcome — the card still slides in, the marker is still
/// dropped, and nothing is thrown.
///
/// It is a seam as well as an implementation: the live screen reads it from a
/// provider, so a test can hand over a silent one and assert on delivery
/// without a speaker.
class ScriptureAnnouncer {
  ScriptureAnnouncer();

  static const _tag = 'PW-SCRIP';

  /// Relative to the `assets/` prefix audioplayers applies for asset sources.
  static const _chimeAsset = 'audio/scripture_chime.wav';

  AudioPlayer? _player;
  FlutterTts? _tts;

  /// Set once a platform has told us it cannot do something, so a device
  /// without a TTS engine is not asked again on every verse for an hour.
  bool _audioUnavailable = false;
  bool _voiceUnavailable = false;

  /// Announces an arrival. Returns as soon as the chime is away — the caller is
  /// a widget on a recording screen and must not be held up.
  ///
  /// [sound] and [voice] come from the walker's settings and the live mute
  /// control; the haptic and the screen-reader announcement are not switchable,
  /// because they are the two channels that still work with the ringer off.
  ///
  /// [view] is the window to announce into, from `View.of(context)`. Null skips
  /// the assistive announcement — the arrival card is a live region in its own
  /// right, so a screen reader still reaches the verse.
  Future<void> announce(
    ScripturePrompt prompt, {
    required bool sound,
    required bool voice,
    FlutterView? view,
  }) async {
    // Screen readers first: an assistive announcement queued behind a 1.7 s
    // chime is an announcement that arrives late.
    _announceToScreenReaders(prompt, view);
    _haptic();
    if (sound) await _chime();
    if (voice) await _speak(prompt);
  }

  /// Stops anything still being spoken — the mute control, a pause, the end of
  /// the walk. Safe to call when nothing is playing.
  Future<void> silence() async {
    try {
      await _tts?.stop();
    } catch (_) {
      /* Nothing was speaking, or the engine went away. Either is fine. */
    }
    try {
      await _player?.stop();
    } catch (_) {
      /* As above. */
    }
  }

  void dispose() {
    unawaited(silence());
    try {
      _player?.dispose();
    } catch (_) {
      /* Disposing a player that never initialised. */
    }
    _player = null;
    _tts = null;
  }

  // ------------------------------------------------------------- channels ---

  void _announceToScreenReaders(ScripturePrompt prompt, FlutterView? view) {
    if (view == null) return;
    try {
      unawaited(
        SemanticsService.sendAnnouncement(view, prompt.spoken, TextDirection.ltr),
      );
    } catch (error) {
      AppLogger.info(_tag, 'semantics announcement failed (${error.runtimeType})');
    }
  }

  void _haptic() {
    try {
      // Deliberately the lightest of the three: this is a hand on a shoulder,
      // not a notification demanding to be dealt with.
      unawaited(HapticFeedback.lightImpact());
    } catch (_) {
      /* No motor, or a platform without one. */
    }
  }

  Future<void> _chime() async {
    if (_audioUnavailable) return;
    try {
      final player = _player ??= await _buildPlayer();
      await player.stop();
      await player.play(AssetSource(_chimeAsset));
    } catch (error) {
      _audioUnavailable = true;
      AppLogger.info(_tag, 'chime unavailable (${error.runtimeType}) — silent from here');
    }
  }

  Future<AudioPlayer> _buildPlayer() async {
    final player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
    // `respectSilence` is the point of this configuration: someone who has
    // switched their phone to silent has already said what they want, and a
    // contemplative app is the last thing that should argue. `duckOthers`
    // lowers whatever they are listening to for the chime rather than stopping
    // it — a walk with music on stays a walk with music on.
    await player.setAudioContext(
      AudioContextConfig(
        respectSilence: true,
        focus: AudioContextConfigFocus.duckOthers,
      ).build(),
    );
    return player;
  }

  Future<void> _speak(ScripturePrompt prompt) async {
    if (_voiceUnavailable) return;
    try {
      final tts = _tts ??= await _buildTts();
      await tts.stop();
      await tts.speak(prompt.spoken);
    } catch (error) {
      _voiceUnavailable = true;
      AppLogger.info(_tag, 'voice unavailable (${error.runtimeType}) — text only from here');
    }
  }

  Future<FlutterTts> _buildTts() async {
    final tts = FlutterTts();
    // Slower than the default: this is a verse being read to someone walking,
    // not a notification being got through.
    await tts.setSpeechRate(0.44);
    await tts.setPitch(1.0);
    await tts.setVolume(0.9);
    // iOS only, and no-ops elsewhere. `ambient` is the category the Silent
    // switch actually silences, which is the whole reason it is chosen.
    await tts.setSharedInstance(true);
    await tts.setIosAudioCategory(
      IosTextToSpeechAudioCategory.ambient,
      const [],
    );
    return tts;
  }
}

/// One announcer for the app, disposed with the container so no engine or audio
/// session is left holding on after a walk.
final scriptureAnnouncerProvider = Provider<ScriptureAnnouncer>((ref) {
  final announcer = ScriptureAnnouncer();
  ref.onDispose(announcer.dispose);
  return announcer;
});
