import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/app_logger.dart';
import '../domain/scripture_history.dart';
import '../domain/scripture_prompt.dart';
import 'scripture_row_mapper.dart';

/// The two local sources of prompts, under the network.
///
/// A walk happens outdoors and often without signal, so the library has to be
/// readable with the radio off. Two layers do that:
///
///  * the **bundled asset** — `assets/scripture/prompts.json`, shipped in the
///    binary. It is the floor: a device that has never once been online still
///    has a walk's worth of verses. It cannot be empty and cannot fail for a
///    reason worth reporting.
///  * the **cache** — the last set successfully read from Supabase, written
///    through on every successful sync. This is what carries an admin's
///    additions into airplane mode.
///
/// Alongside them sits the **delivery history** — which passages this member has
/// already received, and when. It lives here rather than on the server's
/// critical path for the same reason the library does: selection happens at the
/// top of a walk, outdoors, possibly with the radio off, and it must have an
/// answer immediately. `scripture_deliveries` is the mirror that carries this
/// to a second phone; on a walk, what is stored here is the truth.
///
/// Nothing here throws. Every method answers with an empty result when it
/// cannot answer properly, and the caller above decides what that means.
class ScripturePromptStore {
  const ScripturePromptStore();

  static const _tag = 'PW-SCRIP';
  static const _cacheKey = 'scripture.prompts.v1';
  static const _historyKey = 'scripture.history.v1';
  static const _assetPath = 'assets/scripture/prompts.json';

  /// The ceiling on the stored record, in passages.
  ///
  /// One entry per prompt rather than one per delivery, so at any library size
  /// this project will reach — the NLT ceiling alone caps it at 500 — this is
  /// never hit. It is a bound against the unbounded case, not a retention
  /// policy: a library that grows past it, or a corrupt write that invents ids,
  /// must not be able to grow a member's preferences file forever.
  static const historyLimit = 1000;

  /// The last set synced from Supabase, or empty if there has never been one.
  Future<List<ScripturePrompt>> readCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return const [];
      return scripturePromptsFromRows(jsonDecode(raw) as List<dynamic>);
    } catch (error) {
      // A corrupt or unreadable cache is a missing cache. Say so once and let
      // the bundled floor take over.
      AppLogger.warn(_tag, 'prompt cache unreadable — using the bundled set', error);
      return const [];
    }
  }

  /// Write-through after a successful sync. Fire-and-forget by design: a walk
  /// must never wait on, or fail because of, a cache write.
  Future<void> writeCache(List<ScripturePrompt> prompts) async {
    if (prompts.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        jsonEncode([for (final p in prompts) scripturePromptToRow(p)]),
      );
    } catch (error) {
      AppLogger.warn(_tag, 'could not cache prompts', error);
    }
  }

  /// The set shipped in the binary. **Public-domain WEBBE only**, whatever
  /// `SCRIPTURE_TRANSLATION` says the app delivers — see the asset's own
  /// `licence` field and `supabase/seed/scripture_prompts_seed.sql`.
  ///
  /// Bundling a licensed translation inside the binary is a wider distribution
  /// question than a row on a server, and it is not one this project has an
  /// answer to yet. So a device that falls this far back reads WEBBE and
  /// credits WEBBE; each prompt carries its own translation, so nothing here
  /// inherits a mark from the configured edition.
  Future<List<ScripturePrompt>> readBundled() async {
    try {
      final raw = await rootBundle.loadString(_assetPath);
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return scripturePromptsFromRows(decoded['prompts'] as List<dynamic>);
    } catch (error) {
      // Only reachable if the asset is missing from the build, which is a
      // packaging fault rather than a runtime condition — but it still must not
      // take a recording with it.
      AppLogger.error(_tag, 'bundled prompts asset unreadable', error);
      return const [];
    }
  }

  // -------------------------------------------------------- what was given ---

  /// Everything this member has already received, or an empty history.
  ///
  /// Read once at the top of a walk, and again whenever the queue is rebuilt.
  /// An unreadable record reads as "nothing seen yet", which costs freshness
  /// for one walk and never costs the walk itself — the alternative, refusing to
  /// select until history can be read, would make a corrupt preferences file
  /// into a silent walk.
  Future<ScriptureHistory> readHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_historyKey);
      if (raw == null || raw.isEmpty) return const ScriptureHistory.empty();
      return ScriptureHistory.fromJson(jsonDecode(raw));
    } catch (error) {
      AppLogger.warn(_tag, 'delivery history unreadable — starting fresh', error);
      return const ScriptureHistory.empty();
    }
  }

  /// Persists the record, capped. Never awaited on a walk: a verse has already
  /// been delivered by the time this is called, and a failed write costs the
  /// memory of it rather than the verse.
  Future<void> writeHistory(ScriptureHistory history) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _historyKey,
        jsonEncode(history.capped(historyLimit).toJson()),
      );
    } catch (error) {
      AppLogger.warn(_tag, 'could not record what was delivered', error);
    }
  }

  /// "Start the library fresh" — the member deliberately choosing to walk the
  /// same passages again.
  Future<void> clearHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_historyKey);
    } catch (error) {
      AppLogger.warn(_tag, 'could not clear delivery history', error);
    }
  }
}
