import 'dart:async';

import '../../../core/config/app_config.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/utils/app_logger.dart';
import '../../devotionals/domain/devotional.dart' show DevotionalCategory;
import '../domain/bible_translation.dart';
import '../domain/scripture_library.dart';
import '../domain/scripture_prompt.dart';
import '../domain/scripture_repository.dart';
import '../domain/scripture_submission.dart';
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
  const SupabaseScriptureRepository([
    this._store = const ScripturePromptStore(),
    this._translationId,
  ]);

  final ScripturePromptStore _store;

  /// Which edition a walk draws from. Null defers to the build's configured
  /// default, which is what every caller outside a test does — the provider
  /// passes it explicitly so switching the default rebuilds the repository.
  final String? _translationId;

  BibleTranslation get _translation =>
      BibleTranslation.of(_translationId ?? AppConfig.scriptureTranslation);

  static const _tag = 'PW-SCRIP';

  /// Long enough for a slow connection, short enough that a warm-up prefetch on
  /// a dead network gives up while the walker is still on the record screen.
  static const _timeout = Duration(seconds: 8);

  @override
  Future<List<ScripturePrompt>> publishedPrompts({
    DevotionalCategory? category,
  }) async => (await publishedLibrary(category: category)).prompts;

  @override
  Future<ScriptureLibrary> publishedLibrary({
    DevotionalCategory? category,
  }) async {
    final fresh = await _fetch();
    if (fresh.isNotEmpty) {
      // Write-through, unawaited: the verses are already in hand and a cache
      // write is not something a walk should wait on. The *whole* library is
      // cached, both editions included, so switching the default translation
      // does not have to wait for a re-sync.
      unawaited(_store.writeCache(fresh));
      return _select(fresh, category, ScriptureLibrarySource.network);
    }

    final cached = await _store.readCache();
    if (cached.isNotEmpty) {
      AppLogger.info(_tag, 'using the cached prompt library');
      return _select(cached, category, ScriptureLibrarySource.cache);
    }

    // The offline floor, and the one place the configured translation does not
    // get its way: what is bundled in the binary is public-domain WEBBE, and
    // shipping a licensed translation inside the app is a wider distribution
    // question than a row on a server. Said out loud in the log because a
    // walker on an NLT build reading WEBBE verses is a thing worth being able
    // to explain. The verses still carry their own credit — each bundled row
    // says 'WEBBE', so nothing inherits NLT's mark.
    final bundled = await _store.readBundled();
    AppLogger.info(
      _tag,
      'using the bundled prompt library (${BibleTranslation.fallback.id}) — '
      '${_translation.id} is not shipped offline',
    );
    if (bundled.isEmpty) {
      AppLogger.error(_tag, 'no prompts from any source — the walk is silent');
      return const ScriptureLibrary.empty();
    }
    return _select(bundled, category, ScriptureLibrarySource.bundled);
  }

  /// Theme first, then edition — the two filters a walk applies to the library.
  ///
  /// [source] rides along untouched. Filtering does not change where a set came
  /// from, and where it came from is the fact that explains the other four.
  ScriptureLibrary _select(
    List<ScripturePrompt> prompts,
    DevotionalCategory? category,
    ScriptureLibrarySource source,
  ) {
    final available = _inCategory(prompts, category);
    return _inTranslation(available, source);
  }

  /// Only the configured edition is delivered, so both sets can live in the
  /// table at once and the build decides which is heard. Prayers come through
  /// whatever is configured: they quote nobody, so they belong to every
  /// edition rather than to none.
  ///
  /// If that leaves no scripture at all — an NLT build whose licensed rows have
  /// not been seeded yet — the whole library is delivered instead, which in
  /// practice means WEBBE, because WEBBE is what is seeded and bundled. A walk
  /// with the wrong edition is a disappointment; a walk with nothing to read is
  /// the failure this feature exists to avoid. It is logged with both editions
  /// named, because a walker asking "why isn't this the NLT" deserves an answer
  /// that does not require reading the source.
  ScriptureLibrary _inTranslation(
    List<ScripturePrompt> prompts,
    ScriptureLibrarySource source,
  ) {
    final wanted = _translation;
    final selected = [
      for (final prompt in prompts)
        if (!prompt.translationInfo.isQuotation ||
            prompt.translationInfo == wanted)
          prompt,
    ];
    if (selected.any((p) => p.translationInfo.isQuotation)) {
      return ScriptureLibrary(
        prompts: selected,
        source: source,
        requested: wanted,
        available: prompts,
      );
    }

    if (prompts.any((p) => p.translationInfo.isQuotation)) {
      final falling = {
        for (final p in prompts)
          if (p.translationInfo.isQuotation) p.translationInfo.id,
      }.join(', ');
      AppLogger.warn(
        _tag,
        'no ${wanted.id} prompts in the ${source.label} library — '
        'falling back to what is there ($falling). '
        'Seed the ${wanted.id} rows, or set SCRIPTURE_TRANSLATION back to '
        '${BibleTranslation.fallback.id}.',
      );
    }
    return ScriptureLibrary(
      prompts: prompts,
      source: source,
      requested: wanted,
      available: prompts,
      fellBack: true,
    );
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
    // The curated library: drafts included, unreviewed submissions excluded.
    //
    // A pending submission cannot be published — the check constraint
    // `scripture_prompts_published_is_approved` refuses it — so listing one
    // here would put a Publish button on a row that answers with a 23514. It
    // belongs in the submissions queue, which is where the decision that makes
    // it publishable is taken.
    final rows = await supabase
        .from('scripture_prompts')
        .select(scripturePromptColumns)
        .eq('status', 'approved')
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

  // ------------------------------------------------- member contributions ---

  @override
  Future<void> submitPrompt(ScriptureSubmissionDraft draft) async {
    final me = supabase.auth.currentUser?.id;
    if (me == null) {
      throw const AppException('Sign in again, then send your submission.');
    }

    final reference = draft.reference.trim();
    if (reference.isEmpty) {
      throw const AppException(
        'Name the passage or the prayer — "Psalm 121:1-2" is enough.',
      );
    }
    if (draft.reflection.trim().isEmpty) {
      throw const AppException(
        'Add a line of your own about why this one. That part is the point.',
      );
    }

    await supabase.from('scripture_prompts').insert({
      'reference': reference,
      'body': draft.body.trim(),
      // ⚖️ Hard-wired, not taken from the draft. A member's submission carries
      // the public-domain edition or nothing; the insert policy refuses
      // anything else outright, and there is no field on the form that could
      // send a different value. Text with no body quotes nobody and credits
      // nobody, which is why an empty body drops the translation with it.
      'translation': draft.body.trim().isEmpty
          ? ''
          : ScriptureSubmissionDraft.allowedTranslation.id,
      'kind': draft.kind.name,
      'category': draft.category.name,
      'contributor_note': draft.reflection.trim(),
      'submitted_by': me,
      // Sent explicitly so the row that reaches the policy says what it is,
      // rather than relying on two column defaults to agree with it.
      'status': 'pending',
      'is_published': false,
    });
  }

  @override
  Future<List<ScriptureSubmission>> mySubmissions() async {
    final me = supabase.auth.currentUser?.id;
    if (me == null) return const [];

    final rows = await supabase
        .from('scripture_prompts')
        .select(scripturePromptColumns)
        .eq('submitted_by', me)
        .order('created_at', ascending: false);

    return [for (final row in rows) scriptureSubmissionFromRow(row)];
  }

  @override
  Future<List<ScriptureSubmission>> submissions({
    SubmissionStatus? status,
  }) async {
    // Member submissions only — `submitted_by` not null. The admin-curated
    // library has its own screen and does not belong in a review queue.
    var query = supabase
        .from('scripture_prompts')
        .select(scripturePromptColumns)
        .not('submitted_by', 'is', null);
    if (status != null) query = query.eq('status', status.name);

    final rows = await query.order('created_at', ascending: false);
    return [for (final row in rows) scriptureSubmissionFromRow(row)];
  }

  @override
  Future<void> reviewSubmission(
    String id, {
    required SubmissionStatus outcome,
    String reason = '',
  }) async {
    final approving = outcome == SubmissionStatus.approved;
    final rows = await supabase
        .from('scripture_prompts')
        .update({
          'status': outcome.name,
          // Approval publishes. The check constraint
          // `scripture_prompts_published_is_approved` refuses the other
          // combination, so a rejected row cannot be left live by accident.
          'is_published': approving,
          'rejection_reason': approving ? '' : reason.trim(),
        })
        .eq('id', id)
        .select('id');
    if (rows.isEmpty) throw AppException.notFound;
  }
}
