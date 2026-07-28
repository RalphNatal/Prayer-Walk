import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_logger.dart';

/// Touch feedback, with one vocabulary.
///
/// This app spends its time in a hand, outdoors, often with the screen barely
/// glanced at. What a tap *feels* like is a real part of whether it lands. But
/// the same reasoning cuts the other way: a device that buzzes at everything is
/// noise, and noise is the opposite of what this app is for. So the vocabulary
/// is deliberately small and each level means one thing.
///
/// * [selection] — a choice among options. Filter chips, activity type, tabs,
///   switches. The lightest thing the platform has.
/// * [light] — a small deliberate act with a result. Encouraging a walk,
///   dropping a waypoint, confirming in a sheet.
/// * [heavy] — the four moments of a recording: start, pause, resume, finish.
///   These are the ones a walker acts on without looking, and the ones where
///   being wrong costs them the walk.
/// * [failure] — something did not happen. A double knock, distinct from every
///   success pattern, so a failed save is felt as well as read.
///
/// Nothing else. In particular there is no haptic on ordinary navigation, on
/// scrolling, or on anything the platform already handles itself.
///
/// Everything here is fire-and-forget and never throws: a device with no
/// vibrator, or a platform channel that is not ready, must not take a walk down
/// with it.
abstract final class AppHaptics {
  static const _tag = 'PW-HAPTIC';
  static const _prefsKey = 'haptics_enabled';

  /// Whether feedback is on. Mirrors the stored preference so the call sites
  /// stay synchronous — a haptic that had to await a disk read would land after
  /// the thing it is meant to accompany.
  ///
  /// This is the app's own switch. The platform's setting is honoured underneath
  /// it by the OS: Android respects the system haptic toggle for
  /// `HapticFeedback`, and iOS respects both the system setting and Low Power
  /// Mode. Turning this off silences the app on a device where the platform
  /// would still allow it.
  static bool get enabled => _enabled;
  static bool _enabled = true;

  /// Reads the stored preference. Called once from `main`; failure leaves the
  /// default (on) rather than blocking startup.
  static Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_prefsKey) ?? true;
    } catch (error) {
      AppLogger.info(_tag, 'could not read the haptics preference ($error)');
    }
  }

  static Future<void> setEnabled(bool value) async {
    _enabled = value;
    // Confirm the change in the medium being changed: turning it on gives one
    // light tap, so the person knows what they have just switched on.
    if (value) light();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, value);
    } catch (error) {
      AppLogger.info(_tag, 'could not save the haptics preference ($error)');
    }
  }

  /// A choice among options.
  static void selection() => _fire(HapticFeedback.selectionClick);

  /// A small deliberate act with a result.
  static void light() => _fire(HapticFeedback.lightImpact);

  /// Start, pause, resume, finish — the moments of a recording.
  static void heavy() => _fire(HapticFeedback.mediumImpact);

  /// Something did not happen.
  ///
  /// Two knocks rather than one, spaced far enough apart to read as separate.
  /// Nothing else in the vocabulary is a pattern, which is what makes a failure
  /// identifiable without looking.
  static void failure() {
    if (!_enabled) return;
    _fire(HapticFeedback.mediumImpact);
    Future<void>.delayed(
      const Duration(milliseconds: 130),
      () => _fire(HapticFeedback.heavyImpact),
    );
  }

  static void _fire(Future<void> Function() feedback) {
    if (!_enabled) return;
    // Unawaited and swallowed. A missing vibrator is not an error worth
    // surfacing, and this is called from gesture callbacks that cannot wait.
    feedback().catchError((Object error) {
      if (kDebugMode) AppLogger.info(_tag, 'feedback unavailable ($error)');
    });
  }
}
