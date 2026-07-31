import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/app_logger.dart';
import '../../devotionals/domain/devotional.dart' show DevotionalCategory;
import '../domain/scripture_settings.dart';
import 'scripture_row_mapper.dart' show categoryFrom;


class ScriptureSettingsController extends Notifier<ScriptureSettings> {
  static const _tag = 'PW-SCRIP';

  static const _kEnabled = 'scripture.enabled';
  static const _kSource = 'scripture.source';
  static const _kMeters = 'scripture.intervalMeters';
  static const _kSteps = 'scripture.intervalSteps';
  static const _kCategory = 'scripture.category';
  static const _kSound = 'scripture.sound';
  static const _kVoice = 'scripture.voice';
  static const _kTranslation = 'scripture.showTranslation';

  /// Whether the walker has changed something since this controller was built.
  ///
  /// The disk read started in [build] and a choice made by a thumb are in a
  /// race, and the thumb has to win. Without this, a walker who opens the
  /// cadence sheet and taps Steps in the first moments of the app's life can
  /// have the tap overwritten by the stored value landing behind it — and worse
  /// than overwritten: [_persist] writes its keys one at a time, so a [_hydrate]
  /// that interleaves with it reads a half-written record and can resolve
  /// `source` to the fallback while `enabled` is already there. What was chosen
  /// a moment ago is never less current than what was on disk.
  bool _touched = false;

  @override
  ScriptureSettings build() {
    unawaited(_hydrate());
    return const ScriptureSettings();
  }

  Future<void> _hydrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_touched) return;
      // Nothing stored yet: leave the defaults exactly as built, rather than
      // writing them out and pretending they were chosen.
      if (!prefs.containsKey(_kEnabled)) return;

      final categoryName = prefs.getString(_kCategory);
      state = ScriptureSettings(
        enabled: prefs.getBool(_kEnabled) ?? true,
        cadence: ScriptureCadence(
          source: CadenceSource.values.firstWhere(
            (s) => s.name == prefs.getString(_kSource),
            orElse: () => CadenceSource.distance,
          ),
          intervalMeters: prefs.getDouble(_kMeters) ?? 400,
          intervalSteps: prefs.getInt(_kSteps) ?? 500,
        ),
        category: categoryName == null || categoryName.isEmpty
            ? null
            : categoryFrom(categoryName),
        sound: prefs.getBool(_kSound) ?? true,
        voice: prefs.getBool(_kVoice) ?? true,
        showTranslation: prefs.getBool(_kTranslation) ?? true,
      );
    } catch (error) {
      // No store on this platform, or an unreadable one. The defaults are
      // already in state and the walk is unaffected.
      AppLogger.info(_tag, 'settings not restored (${error.runtimeType})');
    }
  }

  void _apply(ScriptureSettings next) {
    // Set before the equality check, not after: a walker who taps the value
    // that happens to already be on screen has still made a choice, and a
    // stored record landing afterwards must not be allowed to change it.
    _touched = true;
    if (next == state) return;
    state = next;
    unawaited(_persist(next));
  }

  Future<void> _persist(ScriptureSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kEnabled, settings.enabled);
      await prefs.setString(_kSource, settings.cadence.source.name);
      await prefs.setDouble(_kMeters, settings.cadence.intervalMeters);
      await prefs.setInt(_kSteps, settings.cadence.intervalSteps);
      await prefs.setString(_kCategory, settings.category?.name ?? '');
      await prefs.setBool(_kSound, settings.sound);
      await prefs.setBool(_kVoice, settings.voice);
      await prefs.setBool(_kTranslation, settings.showTranslation);
    } catch (error) {
      // The choice still holds for this run; it simply will not survive a
      // restart. Not worth interrupting anyone over.
      AppLogger.info(_tag, 'settings not saved (${error.runtimeType})');
    }
  }

  void setEnabled(bool enabled) => _apply(state.copyWith(enabled: enabled));

  void setCadence(ScriptureCadence cadence) =>
      _apply(state.copyWith(cadence: cadence, enabled: true));

  void setSource(CadenceSource source) =>
      _apply(state.copyWith(cadence: state.cadence.copyWith(source: source)));

  /// The custom interval, set in metres and mirrored into steps.
  ///
  /// Both halves are written on purpose. The panel offers one "how often"
  /// control and describes it in both idioms, but only the metres half used to
  /// be stored — so a walker on step cadence who chose a custom interval kept
  /// whichever `intervalSteps` the last preset had left behind, and their
  /// choice did nothing at all. The conversion is the same approximate stride
  /// the presets are built on, which is why the panel keeps saying "roughly".
  void setIntervalMeters(double meters) {
    // Below a couple of hundred metres a verse arrives before the last one has
    // been read, which is the opposite of what this is for.
    final clamped = meters.clamp(200.0, 5000.0);
    _apply(
      state.copyWith(
        cadence: state.cadence.copyWith(
          intervalMeters: clamped,
          intervalSteps: (clamped / kAverageStrideMeters).round(),
        ),
      ),
    );
  }

  void setCategory(DevotionalCategory? category) => _apply(
    category == null
        ? state.copyWith(clearCategory: true)
        : state.copyWith(category: category),
  );

  void setSound(bool sound) => _apply(state.copyWith(sound: sound));

  void setVoice(bool voice) => _apply(state.copyWith(voice: voice));

  void setShowTranslation(bool show) =>
      _apply(state.copyWith(showTranslation: show));
}

final scriptureSettingsProvider =
    NotifierProvider<ScriptureSettingsController, ScriptureSettings>(
      ScriptureSettingsController.new,
    );
