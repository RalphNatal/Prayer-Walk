import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/app_exception.dart';
import '../domain/devotional.dart';
import '../domain/devotional_repository.dart';
import 'devotional_row_mapper.dart';

/// The real `devotionals` table, read and written through RLS.
///
/// The two reads are deliberately different queries rather than one filtered in
/// Dart. [published] is what a member sees and is filtered server-side; [all]
/// returns drafts too and only resolves at all because the caller is an admin —
/// the table's select policy hides unpublished rows from everyone else. If a
/// member screen ever called [all], it would come back with exactly the same
/// rows as [published], because the boundary is the database, not this class.
///
/// Unlike `SupabaseScriptureRepository`, nothing here falls back to a cache. A
/// devotional is read sitting still, with a "Retry" a thumb away; the offline
/// floor exists for scripture because that is read mid-walk where there may be
/// no signal and no second chance.
class SupabaseDevotionalRepository implements DevotionalRepository {
  const SupabaseDevotionalRepository();

  @override
  Future<List<Devotional>> published({DevotionalCategory? category}) async {
    var query = supabase
        .from('devotionals')
        .select(devotionalColumns)
        .eq('is_published', true);
    if (category != null) {
      query = query.eq('category', category.name);
    }
    // Newest publication first. `updated_at` breaks the tie for rows published
    // in the same instant by the seed.
    final rows = await query
        .order('published_at', ascending: false, nullsFirst: false)
        .order('updated_at', ascending: false);
    return devotionalsFromRows(rows);
  }

  @override
  Future<List<Devotional>> all() async {
    final rows = await supabase
        .from('devotionals')
        .select(devotionalColumns)
        .order('updated_at', ascending: false);
    return devotionalsFromRows(rows);
  }

  @override
  Future<Devotional> byId(String id) async {
    final rows = await supabase
        .from('devotionals')
        .select(devotionalColumns)
        .eq('id', id);
    // Empty means gone *or* hidden by RLS — a draft opened from a stale link.
    // Both are "that's not there" to the person reading.
    if (rows.isEmpty) throw AppException.notFound;
    return devotionalFromRow(rows.first);
  }

  @override
  Future<Devotional> save(
    DevotionalDraft draft, {
    required String authorName,
  }) async {
    final now = DateTime.now().toUtc();
    final payload = <String, dynamic>{
      'title': draft.title.trim(),
      'summary': draft.summary.trim(),
      'body': draft.body.trim(),
      'scripture_ref': draft.scriptureRef.trim(),
      'scripture_text': draft.scriptureText.trim(),
      // Null rather than '' when nothing is quoted: the column is nullable
      // precisely so "no passage" and "a passage from an unnamed edition" stay
      // distinguishable in the table.
      'translation': draft.scriptureText.trim().isEmpty
          ? null
          : draft.translation.trim(),
      'category': draft.category.name,
      'is_published': draft.isPublished,
      'read_minutes': estimateReadMinutes(draft.body),
    };

    final id = draft.id;
    if (id == null) {
      return devotionalFromRow(
        await supabase
            .from('devotionals')
            .insert({
              ...payload,
              // Stamped from the session, never from the form: the byline has
              // to be whoever is actually signed in.
              'author_id': supabase.auth.currentUser?.id,
              'author_name': authorName,
              'published_at': draft.isPublished ? now.toIso8601String() : null,
            })
            .select(devotionalColumns)
            .single(),
      );
    }

    // An edit keeps the original byline — the person who wrote it — and keeps
    // the original publication date if it was already live. Republishing
    // something that was pulled down sets a fresh one.
    final existing = await byId(id);
    final rows = await supabase
        .from('devotionals')
        .update({
          ...payload,
          'published_at': draft.isPublished
              ? (existing.publishedAt ?? now).toUtc().toIso8601String()
              : null,
        })
        .eq('id', id)
        .select(devotionalColumns);
    if (rows.isEmpty) throw AppException.notFound;
    return devotionalFromRow(rows.first);
  }

  @override
  Future<Devotional> setPublished(String id, {required bool published}) async {
    final existing = await byId(id);
    final rows = await supabase
        .from('devotionals')
        .update({
          'is_published': published,
          'published_at': published
              ? (existing.publishedAt ?? DateTime.now())
                    .toUtc()
                    .toIso8601String()
              : null,
        })
        .eq('id', id)
        .select(devotionalColumns);
    if (rows.isEmpty) throw AppException.notFound;
    return devotionalFromRow(rows.first);
  }

  @override
  Future<void> delete(String id) async {
    await supabase.from('devotionals').delete().eq('id', id);
  }
}
