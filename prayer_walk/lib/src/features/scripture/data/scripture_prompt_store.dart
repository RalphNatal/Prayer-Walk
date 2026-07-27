import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/app_logger.dart';
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
/// Nothing here throws. Every method answers with an empty list when it cannot
/// answer with prompts, and the repository above decides what that means.
class ScripturePromptStore {
  const ScripturePromptStore();

  static const _tag = 'PW-SCRIP';
  static const _cacheKey = 'scripture.prompts.v1';
  static const _assetPath = 'assets/scripture/prompts.json';

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

  /// The set shipped in the binary. Public domain text only — see the asset's
  /// own `licence` field and `supabase/seed/scripture_prompts_seed.sql`.
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
}
