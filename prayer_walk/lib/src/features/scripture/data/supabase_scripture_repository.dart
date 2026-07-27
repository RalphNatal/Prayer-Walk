import 'dart:async';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/utils/app_logger.dart';
import '../../devotionals/domain/devotional.dart' show DevotionalCategory;
import '../domain/scripture_prompt.dart';
import '../domain/scripture_repository.dart';
import 'scripture_prompt_store.dart';
import 'scripture_row_mapper.dart';

/// The prompt library, from Supabase, with the ground never falling away.
///
/// [publishedPrompts] is the one method a walk depends on, and it is written so
/// that it cannot fail: Supabase first, then the last-synced cache, then the
/// set bundled in the binary. A walker in a valley with no signal reads the
/// same verses as one on a city street; the only difference is whether an
/// admin's newest addition is among them.
///
/// The whole published library is fetched and cached on every sync rather than
/// only the requested theme. A themed query would leave airplane mode holding
/// one theme's worth of verses, which is the walk most likely to run out.
class SupabaseScriptureRepository implements ScriptureRepository {
  const SupabaseScriptureRepository([this._store = const ScripturePromptStore()]);

  final ScripturePromptStore _store;

  static const _tag = 'PW-SCRIP';

  /// Long enough for a slow connection, short enough that a warm-up prefetch on
  /// a dead network gives up while the walker is still on the record screen.
  static const _timeout = Duration(seconds: 8);

  @override
  Future<List<ScripturePrompt>> publishedPrompts({
    DevotionalCategory? category,
  }) async {
    final fresh = await _fetch();
    if (fresh.isNotEmpty) {
      // Write-through, unawaited: the verses are already in hand and a cache
      // write is not something a walk should wait on.
      unawaited(_store.writeCache(fresh));
      return _inCategory(fresh, category);
    }

    final cached = await _store.readCache();
    if (cached.isNotEmpty) {
      AppLogger.info(_tag, 'using the cached prompt library');
      return _inCategory(cached, category);
    }

    AppLogger.info(_tag, 'using the bundled prompt library');
    return _inCategory(await _store.readBundled(), category);
  }

  /// Supabase, or an empty list. Deliberately swallows: every failure here has
  /// the same answer — read locally — and the walk is not told about any of it.
  Future<List<ScripturePrompt>> _fetch() async {
    try {
      final rows = await supabase
          .from('scripture_prompts')
          .select(scripturePromptColumns)
          .eq('is_published', true)
          .order('sort_order')
          .timeout(_timeout);
      return scripturePromptsFromRows(rows);
    } catch (error) {
      AppLogger.info(
        _tag,
        'prompt sync failed (${error.runtimeType}) — falling back locally',
      );
      return const [];
    }
  }

  static List<ScripturePrompt> _inCategory(
    List<ScripturePrompt> prompts,
    DevotionalCategory? category,
  ) {
    if (category == null) return prompts;
    return prompts.where((p) => p.category == category).toList(growable: false);
  }

  // ------------------------------------------------------- admin curation ---
  //
  // Wired to real queries and scoped by the table's admin policy, but nothing
  // in the app calls them yet: scripture curation lands with the rest of the
  // admin de-mock. They throw like any other write — a failed edit is a failure
  // worth reporting, unlike a failed read on a trail.

  @override
  Future<List<ScripturePrompt>> allPrompts() async {
    final rows = await supabase
        .from('scripture_prompts')
        .select(scripturePromptColumns)
        .order('sort_order');
    return scripturePromptsFromRows(rows);
  }

  @override
  Future<ScripturePrompt> savePrompt(ScripturePromptDraft draft) async {
    final payload = {
      'reference': draft.reference.trim(),
      'body': draft.body.trim(),
      'translation': draft.translation.trim(),
      'kind': draft.kind.name,
      'category': draft.category.name,
      'is_published': draft.isPublished,
      'sort_order': draft.sortOrder,
    };

    final id = draft.id;
    final row = id == null
        ? await supabase
              .from('scripture_prompts')
              .insert(payload)
              .select(scripturePromptColumns)
              .single()
        : await supabase
              .from('scripture_prompts')
              .update(payload)
              .eq('id', id)
              .select(scripturePromptColumns)
              .single();
    return scripturePromptFromRow(row);
  }

  @override
  Future<ScripturePrompt> setPublished(
    String id, {
    required bool published,
  }) async {
    final rows = await supabase
        .from('scripture_prompts')
        .update({'is_published': published})
        .eq('id', id)
        .select(scripturePromptColumns);
    if (rows.isEmpty) throw AppException.notFound;
    return scripturePromptFromRow(rows.first);
  }

  @override
  Future<void> deletePrompt(String id) async {
    await supabase.from('scripture_prompts').delete().eq('id', id);
  }
}
