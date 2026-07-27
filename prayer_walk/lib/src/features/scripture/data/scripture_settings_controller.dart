import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/app_logger.dart';
import '../../devotionals/domain/devotional.dart' show DevotionalCategory;
import '../domain/scripture_settings.dart';
import 'scripture_row_mapper.dart' show categoryFrom;

/// What the walker has decided about scripture on the trail, remembered.
///
/// Deliberately a plain [Notifier] over an [AsyncNotifier]: every reader wants
/// a usable answer synchronously — the record screen paints a control, the
/// recorder decides whether to arm a trigger — and the honest default (on,
/// gentle cadence, sound and voice) is a fine answer for the handful of frames
/// before the stored one arrives. The alternative makes every reader handle a
/// loading state for a preference.
///
/// Stored in `shared_preferences` rather than on the profile row. It is a
/// device-shaped choice — this phone's speaker, this phone's pocket — and it
/// must be readable with no session and no network, which a profile column is
/// not.
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

  @override
  ScriptureSettings build() {
    unawaited(_hydrate());
    return const ScriptureSettings();
  }

  Future<void> _hydrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
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

  void setIntervalMeters(double meters) => _apply(
    state.copyWith(
      cadence: state.cadence.copyWith(
        // Below a couple of hundred metres a verse arrives before the last one
        // has been read, which is the opposite of what this is for.
        intervalMeters: meters.clamp(200, 5000),
      ),
    ),
  );

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
